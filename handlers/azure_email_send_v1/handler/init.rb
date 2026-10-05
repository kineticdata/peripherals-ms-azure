require 'rexml/document'
require 'json'
require 'net/http'
require 'net/https'
require 'openssl'
require 'timeout'
require 'uri'

class AzureEmailSendV1
  # Raised for any failure that has already been translated into a
  # human-readable message.
  class HandlerError < StandardError; end

  # Response returned by http_post.  Header lookups are case-insensitive.
  class HttpResponse
    attr_reader :code, :body

    def initialize(code, body, headers)
      @code = code.to_s
      @body = body.to_s
      @headers = {}
      headers.each { |name, value| @headers[name.to_s.downcase] = value }
    end

    def [](name)
      @headers[name.to_s.downcase]
    end
  end

  # Microsoft cloud endpoints, selected by the azure_cloud property.  GCC
  # (Moderate) tenants use the Global endpoints.
  CLOUDS = {
    "global" => { :name => "Global", :auth => "https://login.microsoftonline.com", :graph => "https://graph.microsoft.com" },
    "gcchigh" => { :name => "GCC High", :auth => "https://login.microsoftonline.us", :graph => "https://graph.microsoft.us" },
    "dod" => { :name => "DoD", :auth => "https://login.microsoftonline.us", :graph => "https://dod-graph.microsoft.us" },
    "china" => { :name => "China", :auth => "https://login.chinacloudapi.cn", :graph => "https://microsoftgraph.chinacloudapi.cn" }
  }
  CLOUD_ALIASES = { "" => "global", "gcc" => "global", "gccmoderate" => "global" }

  # Exchange Online limit on To + CC + BCC for a single message.
  MAX_RECIPIENTS = 500
  # Retries are only attempted for responses where Graph explicitly refused the
  # request (429, 503).  Timeouts are never retried since the message may have
  # already been sent.
  RETRY_CODES = [429, 503]
  MAX_RETRIES = 3
  MAX_RETRY_WAIT = 30
  OPEN_TIMEOUT = 30
  READ_TIMEOUT = 60

  EMAIL_PATTERN = /\A[^@\s<>",;]+@[^@\s<>",;]+\.[^@\s<>",;.]+\z/

  # ==== Parameters
  # * +input+ - The String of Xml that was built by evaluating the node.xml handler template.
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    # Values are not stripped here so that body content is sent exactly as provided.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s
    end

    @debug_logging_enabled = ["yes","true"].include?(@info_values["enable_debug_logging"].to_s.downcase)
    @error_handling = @parameters["error_handling"].to_s.strip

    @tenant_id = @info_values["tenant_id"].to_s
    @client_id = @info_values["client_id"].to_s
    @client_secret = @info_values["client_secret"].to_s
    @azure_cloud = @info_values["azure_cloud"].to_s.strip
    cloud_key = @azure_cloud.downcase.gsub(/[\s_-]/, "")
    @cloud = CLOUDS[CLOUD_ALIASES[cloud_key] || cloud_key]
    endpoints = @cloud || CLOUDS["global"]
    @auth_url = endpoints[:auth]
    @graph_url = "#{endpoints[:graph]}/v1.0"
    @graph_scope = "#{endpoints[:graph]}/.default"
    @auth_label = "the Microsoft identity platform (#{host_of(endpoints[:auth])})"
    @graph_label = "Microsoft Graph (#{host_of(endpoints[:graph])})"

    @from_override = @parameters["from_override"].to_s.strip
    @from_source = @from_override.empty? ? "the handler's from_address property" : "the From (Override) input"
    @from_value = @from_override.empty? ? @info_values["from_address"].to_s : @from_override

    @to = @parameters["to"].to_s
    @cc = @parameters["cc"].to_s
    @bcc = @parameters["bcc"].to_s
    @subject = @parameters["subject"].to_s.strip
    @html_body = @parameters["html_body"].to_s
    @text_body = @parameters["text_body"].to_s
  end

  def execute
    error_message = nil
    @response_code = nil
    @sender = parse_address(@from_value)[:address]

    begin
      @phase = "validating the inputs"
      message = build_message

      @phase = "requesting an access token"
      token = fetch_access_token

      @phase = "sending the email"
      send_mail(token, message)
      log("Email sent from #{@sender} (HTTP #{@response_code}).")
    rescue HandlerError => e
      error_message = e.message
    rescue StandardError => e
      error_message = "An unexpected error occurred while #{@phase}: #{e.class}: #{e.message}"
    end

    if error_message
      log(error_message)
      # Raise the error if instructed to, otherwise will fall through to
      # return an error message.
      raise error_message if @error_handling == "Raise Error"
    end

    # Return (and escape) the results that were defined in the node.xml
    <<-RESULTS
    <results>
      <result name="Response Code">#{escape(@response_code)}</result>
      <result name="From Address">#{escape(@sender)}</result>
      <result name="Handler Error Message">#{escape(error_message)}</result>
    </results>
    RESULTS
  end

  ##############################################################################
  # Validation and message building
  ##############################################################################

  # Validates every input up front and collects all of the problems so they can
  # be reported (and fixed) together.  Returns the Graph message payload.
  def build_message
    problems = []

    missing = ["tenant_id", "client_id", "client_secret"].select { |name| @info_values[name].to_s.empty? }
    unless missing.empty?
      problems << "The handler configuration is missing #{join_list(missing)}. " \
        "Set #{missing.size == 1 ? "it" : "them"} in the handler's properties in Kinetic Task."
    end

    if @cloud.nil?
      problems << "The handler's azure_cloud property '#{@azure_cloud}' is not recognized. Use Global, GCC High, " \
        "DoD, or China (GCC Moderate tenants use Global)."
    end

    if @from_value.strip.empty?
      problems << "No From address: set the handler's from_address property or provide a From (Override) value."
    elsif !parse_address(@from_value)[:valid]
      problems << "The From address '#{@from_value.strip}' (from #{@from_source}) is not a valid email address."
    end

    recipients = {}
    invalid = []
    [["To", @to], ["CC", @cc], ["BCC", @bcc]].each do |label, value|
      parsed = parse_address_list(value)
      recipients[label] = parsed.select { |address| address[:valid] }
      bad = parsed.reject { |address| address[:valid] }
      invalid << "#{label}: #{bad.map { |address| "'#{address[:raw]}'" }.join(", ")}" unless bad.empty?
    end
    problems << "Invalid email address(es) in #{invalid.join("; ")}." unless invalid.empty?

    total = recipients.values.inject(0) { |sum, list| sum + list.size }
    if total == 0 && invalid.empty?
      problems << "At least one recipient is required in To, CC, or BCC."
    elsif total > MAX_RECIPIENTS
      problems << "The message has #{total} recipients; Exchange Online allows at most #{MAX_RECIPIENTS} " \
        "across To, CC, and BCC. Split the recipients across multiple sends."
    end

    problems << "Subject is required." if @subject.empty?

    has_html = !@html_body.strip.empty?
    has_text = !@text_body.strip.empty?
    problems << "Either HTML Body or Text Body is required." if !has_html && !has_text

    raise HandlerError, problems.join(" ") unless problems.empty?

    if has_html && has_text
      log("HTML Body and Text Body were both provided; sending HTML Body and ignoring Text Body.")
    end
    log("Sender: #{@sender} (from #{@from_source}). Recipients: #{recipients["To"].size} To, " \
      "#{recipients["CC"].size} CC, #{recipients["BCC"].size} BCC. Subject: #{@subject}")

    message = {
      "subject" => @subject,
      "body" => has_html ?
        { "contentType" => "HTML", "content" => @html_body } :
        { "contentType" => "Text", "content" => @text_body }
    }
    message["toRecipients"] = recipients["To"].map { |address| to_recipient(address) } unless recipients["To"].empty?
    message["ccRecipients"] = recipients["CC"].map { |address| to_recipient(address) } unless recipients["CC"].empty?
    message["bccRecipients"] = recipients["BCC"].map { |address| to_recipient(address) } unless recipients["BCC"].empty?
    message
  end

  # Splits a comma or semicolon separated list of addresses.  Separators inside
  # quotes or angle brackets are ignored so values such as
  # "Doe, Jane" <jane@example.com> are kept together.  Duplicate addresses are
  # removed (case-insensitive).
  def parse_address_list(value)
    tokens = []
    current = ""
    in_quotes = false
    in_angle = false
    value.to_s.each_char do |char|
      if char == '"' && !in_angle
        in_quotes = !in_quotes
      elsif char == "<" && !in_quotes
        in_angle = true
      elsif char == ">" && !in_quotes
        in_angle = false
      end

      if (char == "," || char == ";") && !in_quotes && !in_angle
        tokens << current
        current = ""
      else
        current << char
      end
    end
    tokens << current

    seen = {}
    tokens.map { |token| token.strip }.reject { |token| token.empty? }.map { |token| parse_address(token) }.select do |address|
      key = address[:address].downcase
      seen[key] ? false : (seen[key] = true)
    end
  end

  # Parses a single address in either "user@example.com" or
  # "Display Name <user@example.com>" form.
  def parse_address(value)
    raw = value.to_s.strip
    match = raw.match(/\A(.*)<([^<>]*)>\s*\z/m)
    if match
      name = match[1].strip.sub(/\A"(.*)"\z/m, '\1').strip
      address = match[2].strip
    else
      name = ""
      address = raw
    end
    { :raw => raw, :name => name, :address => address, :valid => !(address =~ EMAIL_PATTERN).nil? }
  end

  def to_recipient(address)
    email_address = { "address" => address[:address] }
    email_address["name"] = address[:name] unless address[:name].empty?
    { "emailAddress" => email_address }
  end

  ##############################################################################
  # Azure AD token
  ##############################################################################

  def fetch_access_token
    url = "#{@auth_url}/#{URI.encode_www_form_component(@tenant_id)}/oauth2/v2.0/token"
    log("Requesting access token from #{url}")

    form = URI.encode_www_form(
      "client_id" => @client_id,
      "client_secret" => @client_secret,
      "grant_type" => "client_credentials",
      "scope" => @graph_scope
    )
    response = http_post(url, form,
      { "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json" },
      @auth_label, false)

    body = parse_json(response.body)
    code = response.code.to_i
    log("Token response: HTTP #{code}")

    if code == 200 && body.is_a?(Hash) && !body["access_token"].to_s.empty?
      return body["access_token"]
    end
    raise HandlerError, token_error_message(code, body, response.body)
  end

  def token_error_message(code, body, raw_body)
    body = {} unless body.is_a?(Hash)
    description = body["error_description"].to_s.split(/\r?\n/).first.to_s.strip
    aad_code = description[/AADSTS(\d+)/, 1] || Array(body["error_codes"]).first.to_s

    friendly =
      case aad_code
      when "7000215"
        "The client secret is invalid. Make sure the handler's client_secret property contains the secret's " \
          "Value (not its Secret ID) from the Azure app registration."
      when "7000222"
        "The client secret has expired. Create a new secret in the Azure app registration " \
          "(Certificates & secrets) and update the handler's client_secret property."
      when "700016"
        "The client ID was not found in tenant '#{@tenant_id}'. Check the handler's client_id property " \
          "and that the app is registered in this tenant.#{cloud_hint}"
      when "90002"
        "The tenant '#{@tenant_id}' was not found. Check the handler's tenant_id property.#{cloud_hint}"
      when "900382"
        "The tenant and app registration are in a different Microsoft cloud than the handler's azure_cloud property " \
          "(#{(@cloud || CLOUDS["global"])[:name]}). Set azure_cloud to the tenant's cloud: Global, GCC High, DoD, or China."
      when "900023"
        "'#{@tenant_id}' is not a valid tenant identifier. Set the handler's tenant_id property to the " \
          "Directory (tenant) ID GUID or a domain such as contoso.onmicrosoft.com."
      else
        if code == 200
          "Azure AD responded but did not return an access token."
        elsif code == 400 || code == 401
          "Could not get an access token from Azure AD; the tenant_id, client_id, or client_secret property appears to be wrong.#{cloud_hint}"
        elsif code == 429
          "Azure AD is throttling token requests. Try again shortly."
        elsif code >= 500
          "Azure AD returned a server error while issuing an access token. Try again later."
        else
          "Could not get an access token from Azure AD."
        end
      end

    details = []
    if !description.empty?
      details << "Azure AD: #{description}"
    elsif !body["error"].to_s.empty?
      details << "Azure AD: #{body["error"]}"
    elsif !raw_body.to_s.strip.empty? && code != 200
      details << "Response: #{truncate(raw_body)}"
    end
    details << "HTTP #{code}"
    details << "correlation-id: #{body["correlation_id"]}" unless body["correlation_id"].to_s.empty?

    "#{friendly} (#{details.join("; ")})"
  end

  ##############################################################################
  # Graph sendMail
  ##############################################################################

  def send_mail(token, message)
    url = "#{@graph_url}/users/#{URI.encode_www_form_component(@sender)}/sendMail"
    log("Sending email via #{url}")

    payload = JSON.generate({ "message" => message, "saveToSentItems" => true })
    headers = {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json; charset=utf-8",
      "Accept" => "application/json"
    }

    retries = 0
    loop do
      response = http_post(url, payload, headers, @graph_label, true)
      code = response.code.to_i
      log("sendMail response: HTTP #{code}")
      return if code >= 200 && code < 300

      if RETRY_CODES.include?(code) && retries < MAX_RETRIES
        retries += 1
        wait = retry_wait_seconds(response, retries)
        log("Microsoft Graph returned HTTP #{code}; retry #{retries} of #{MAX_RETRIES} in #{wait} seconds.")
        sleep(wait)
        next
      end

      raise HandlerError, graph_error_message(code, response, retries)
    end
  end

  def retry_wait_seconds(response, retries)
    retry_after = Integer(response["Retry-After"].to_s) rescue nil
    wait = (retry_after && retry_after > 0) ? retry_after : 2 ** retries
    [wait, MAX_RETRY_WAIT].min
  end

  def graph_error_message(code, response, retries)
    body = parse_json(response.body)
    error = (body.is_a?(Hash) && body["error"].is_a?(Hash)) ? body["error"] : {}
    graph_code = error["code"].to_s
    graph_message = error["message"].to_s
    inner_error = error["innerError"].is_a?(Hash) ? error["innerError"] : {}
    request_id = response["request-id"] || inner_error["request-id"]
    retried = retries > 0 ? " (after #{retries} #{retries == 1 ? "retry" : "retries"})" : ""

    access_denied = "The app is not allowed to send mail as #{@sender}. Make sure the app registration has the " \
      "Mail.Send application permission with admin consent granted, and that no Exchange Online application " \
      "access policy or RBAC for Applications scope excludes this mailbox."
    not_found = "The sender mailbox #{@sender} was not found. It must be an Exchange Online user or shared " \
      "mailbox in this tenant."
    too_large = "The message is too large to send. Reduce the size of the body."

    friendly =
      case graph_code
      when "ErrorAccessDenied", "ErrorSendAsDenied", "Authorization_RequestDenied", "AccessDenied"
        access_denied
      when "ErrorInvalidUser", "ResourceNotFound", "Request_ResourceNotFound", "ErrorNonExistentMailbox"
        not_found
      when "MailboxNotEnabledForRESTAPI", "MailboxNotSupportedForRESTAPI"
        "The sender mailbox #{@sender} cannot be used with Microsoft Graph. It may be inactive, unlicensed, " \
          "soft-deleted, or hosted on-premises."
      when "ErrorInvalidRecipients"
        "Exchange Online rejected one or more recipients. Check the To, CC, and BCC addresses."
      when "ErrorMessageSizeExceeded", "RequestEntityTooLarge"
        too_large
      when "ErrorExceededMessageLimit", "ErrorQuotaExceeded"
        "The sender mailbox #{@sender} has reached an Exchange Online sending limit. Try again later or use a different sender."
      when "InvalidAuthenticationToken"
        "Microsoft Graph rejected the access token. Check that the app registration belongs to tenant '#{@tenant_id}'.#{cloud_hint}"
      else
        if code == 400
          "Microsoft Graph rejected the request as invalid."
        elsif code == 401
          "Microsoft Graph rejected the access token. Check that the app registration belongs to tenant '#{@tenant_id}'.#{cloud_hint}"
        elsif code == 403
          access_denied
        elsif code == 404
          not_found
        elsif code == 413
          too_large
        elsif code == 429
          "Microsoft Graph is throttling requests for this app or mailbox#{retried}. The email was not sent; try again later."
        elsif code == 503
          "Microsoft Graph is temporarily unavailable#{retried}. The email was not sent; try again later."
        elsif code >= 500
          "Microsoft Graph returned a server error. The email may or may not have been sent; check the Sent Items " \
            "folder of #{@sender} before trying again."
        else
          "Microsoft Graph returned an unexpected response."
        end
      end

    details = []
    if !graph_code.empty?
      details << "Graph: #{graph_code}#{graph_message.empty? ? "" : " - #{graph_message}"}"
    elsif !response.body.to_s.strip.empty?
      details << "Response: #{truncate(response.body)}"
    end
    details << "HTTP #{code}"
    details << "request-id: #{request_id}" unless request_id.to_s.empty?

    "#{friendly} (#{details.join("; ")})"
  end

  ##############################################################################
  # HTTP
  ##############################################################################

  # Posts the body to the url and returns an HttpResponse for any HTTP status.
  # Network level failures are translated into a HandlerError.  +sending+
  # indicates the request is the sendMail call, where a failure after the
  # request was written means the email may already have been sent.
  #
  # Under JRuby (Kinetic Task) requests are sent with Java's HttpURLConnection,
  # which uses the JVM's TLS implementation.  JRuby's OpenSSL layer can fail
  # large HTTPS request bodies (such as a large HTML body) with "read would
  # block".  Net::HTTP is used when running outside of JRuby.
  def http_post(url, body, headers, label, sending)
    @response_code = nil
    response = defined?(JRUBY_VERSION) ?
      java_http_post(url, body, headers, label, sending) :
      net_http_post(url, body, headers, label, sending)
    @response_code = response.code.to_i
    response
  end

  def java_http_post(url, body, headers, label, sending)
    stage = :connect
    connection = java.net.URL.new(url).openConnection
    connection.setRequestMethod("POST")
    connection.setInstanceFollowRedirects(false)
    connection.setUseCaches(false)
    connection.setConnectTimeout(OPEN_TIMEOUT * 1000)
    connection.setReadTimeout(READ_TIMEOUT * 1000)
    headers.each { |name, value| connection.setRequestProperty(name.to_s, value.to_s) }
    # The body is buffered rather than streamed (setFixedLengthStreamingMode):
    # in streaming mode Java discards the response body of a 401 that includes
    # an authentication challenge, which hides Azure AD and Graph error details.
    connection.setDoOutput(true)
    connection.connect

    stage = :write
    output = connection.getOutputStream
    output.write(body.to_s.to_java_bytes)
    output.close

    stage = :read
    code = connection.getResponseCode
    stream = code >= 400 ? connection.getErrorStream : connection.getInputStream
    response_body = stream.nil? ? "" : read_java_stream(stream)
    response_headers = {}
    connection.getHeaderFields.each do |name, values|
      response_headers[name] = values.to_a.join(", ") unless name.nil?
    end
    HttpResponse.new(code, response_body, response_headers)
  rescue Java::JavaNet::SocketTimeoutException => e
    if stage == :connect
      raise HandlerError, "Timed out after #{OPEN_TIMEOUT} seconds connecting to #{label}. Check network " \
        "connectivity and any proxy or firewall rules between Kinetic Task and Microsoft."
    else
      raise HandlerError, timeout_message(label, sending)
    end
  rescue Java::JavaNet::UnknownHostException => e
    raise HandlerError, "Could not connect to #{label}: unknown host #{e.message}. Check DNS and network " \
      "connectivity from the Kinetic Task server."
  rescue Java::JavaxNetSsl::SSLException => e
    raise HandlerError, tls_message(label, e.message)
  rescue Java::JavaNet::ConnectException, Java::JavaNet::NoRouteToHostException => e
    raise HandlerError, connect_message(label, e.message)
  rescue Java::JavaIo::IOException => e
    raise HandlerError, stage == :connect ? connect_message(label, e.message) : interrupted_message(label, e.message, sending)
  rescue Java::JavaLang::Exception => e
    raise HandlerError, "An unexpected error occurred communicating with #{label}: #{e.class.name}: #{e.message}"
  end

  def read_java_stream(stream)
    output = java.io.ByteArrayOutputStream.new
    buffer = Java::byte[65536].new
    while (count = stream.read(buffer)) != -1
      output.write(buffer, 0, count)
    end
    String.from_java_bytes(output.toByteArray)
  ensure
    stream.close
  end

  def net_http_post(url, body, headers, label, sending)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |name, value| request[name] = value }
    request.body = body

    response = http.request(request)
    response_headers = {}
    response.each_header { |name, value| response_headers[name] = value }
    HttpResponse.new(response.code, response.body, response_headers)
  rescue Timeout::Error => e
    if defined?(Net::OpenTimeout) && e.is_a?(Net::OpenTimeout)
      raise HandlerError, "Timed out after #{OPEN_TIMEOUT} seconds connecting to #{label}. Check network " \
        "connectivity and any proxy or firewall rules between Kinetic Task and Microsoft."
    else
      raise HandlerError, timeout_message(label, sending)
    end
  rescue SocketError => e
    raise HandlerError, "Could not connect to #{label}: #{e.message}. Check DNS and network connectivity " \
      "from the Kinetic Task server."
  rescue OpenSSL::SSL::SSLError => e
    raise HandlerError, tls_message(label, e.message)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT => e
    raise HandlerError, connect_message(label, e.message)
  rescue Errno::ECONNRESET, Errno::EPIPE, EOFError => e
    raise HandlerError, interrupted_message(label, e.message, sending)
  end

  def timeout_message(label, sending)
    if sending
      "Timed out after #{READ_TIMEOUT} seconds waiting for Microsoft Graph to respond. The email may or may not " \
        "have been sent; check the Sent Items folder of #{@sender} before trying again."
    else
      "Timed out waiting for a response from #{label}. Try again later."
    end
  end

  def tls_message(label, detail)
    "Could not establish a secure (TLS) connection to #{label}: #{detail}. A proxy that intercepts TLS " \
      "traffic or an outdated certificate store is a common cause."
  end

  def connect_message(label, detail)
    "Could not connect to #{label}: #{detail}. Check network connectivity and any proxy or firewall rules " \
      "between Kinetic Task and Microsoft."
  end

  def interrupted_message(label, detail, sending)
    message = "The connection to #{label} was interrupted: #{detail}."
    message << " The email may or may not have been sent; check the Sent Items folder of #{@sender} before trying again." if sending
    message
  end

  ##############################################################################
  # General handler utility functions
  ##############################################################################

  def parse_json(string)
    JSON.parse(utf8(string))
  rescue JSON::ParserError
    nil
  end

  # Appended to errors that a tenant in a different Microsoft cloud can cause.
  def cloud_hint
    " If this tenant is in a different Microsoft cloud (such as GCC High or DoD), set the handler's azure_cloud " \
      "property; it is currently #{(@cloud || CLOUDS["global"])[:name]}."
  end

  def host_of(url)
    url.to_s[%r{\Ahttps?://([^/:?#]+)}i, 1].to_s
  end

  def join_list(items)
    items.size <= 1 ? items.join : "#{items[0..-2].join(", ")} and #{items[-1]}"
  end

  # Response bodies are binary strings; this makes them safe to parse and to
  # include in messages.
  def utf8(string)
    value = string.to_s.dup.force_encoding("UTF-8")
    return value if value.valid_encoding?
    value.encode("UTF-16BE", :invalid => :replace, :undef => :replace, :replace => "?").encode("UTF-8")
  end

  def truncate(string, length = 300)
    value = utf8(string).strip.gsub(/\s+/, " ")
    value.length > length ? "#{value[0, length]}..." : value
  end

  # Never pass the client secret, access token, recipient addresses, or body
  # content to this method.
  def log(message)
    puts "[azure_email_send_v1] #{message}" if @debug_logging_enabled
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end
