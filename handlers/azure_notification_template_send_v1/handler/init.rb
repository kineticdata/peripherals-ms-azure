require 'rexml/document'
require 'json'
require 'net/http'
require 'net/https'
require 'openssl'
require 'timeout'
require 'uri'
require 'erb'
require 'date'
require 'securerandom'

class AzureNotificationTemplateSendV1
  # Raised for any failure that has already been translated into a
  # human-readable message.
  class HandlerError < StandardError; end

  AUTH_URL = "https://login.microsoftonline.com"
  GRAPH_URL = "https://graph.microsoft.com/v1.0"
  AUTH_LABEL = "the Microsoft identity platform (login.microsoftonline.com)"
  GRAPH_LABEL = "Microsoft Graph (graph.microsoft.com)"
  UPLOAD_LABEL = "the Outlook attachment upload service (outlook.office.com)"

  # Exchange Online limit on To + CC + BCC for a single message.
  MAX_RECIPIENTS = 500
  DEFAULT_MAX_ATTACHMENT_SIZE_MB = 25
  # Microsoft Graph rejects requests larger than 4 MB.  A message whose sendMail
  # request (including base64 encoded attachments) fits under this size is sent
  # with a single call.  Larger messages are created as a draft, the attachments
  # are added to the draft one at a time, and the draft is then sent.
  SINGLE_REQUEST_MAX_BYTES = 3_500_000
  # Files smaller than this are added to a draft with a single request.  Larger
  # files are uploaded in chunks through an upload session.
  UPLOAD_SESSION_MIN_BYTES = 3 * 1024 * 1024
  UPLOAD_CHUNK_BYTES = 10 * 320 * 1024
  # Retries are only attempted for responses where the service explicitly
  # refused the request (429, 503).  Timeouts are never retried since the
  # message may have already been sent.
  RETRY_CODES = [429, 503]
  MAX_RETRIES = 3
  MAX_RETRY_WAIT = 30
  MAX_REDIRECTS = 5
  MAX_SNIPPET_DEPTH = 10
  OPEN_TIMEOUT = 30
  READ_TIMEOUT = 60
  UPLOAD_READ_TIMEOUT = 120

  CONTENT_FIELDS = ["Subject", "HTML Content", "Text Content"]
  TEMPLATE_ATTACHMENTS_FIELD = "Template Attachments"
  SNIPPET_PATTERN = /\$\{snippet\('(.*?)'\)\}/
  ATTACHMENT_PATTERN = /\$\{attachment\('(.*?)'\)\}/
  APPEARANCE_PATTERN = /\$\{appearance\('(.*?)'\)\}(?!('\)\}))/
  FORMAT_PATTERN = /\A\{format\('(.*?)'\)\}\z/
  PLACEHOLDER_PATTERN = /\$\{(\w+)\('(.*?)'\)\}/
  INLINE_IMAGE_PATTERN = /(["'])cid:(https?:\/\/[^"']+)\1/i
  REDIRECT_CODES = [301, 302, 303, 307, 308]
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
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end

    @debug_logging_enabled = ["yes","true"].include?(@info_values["enable_debug_logging"].to_s.downcase)
    @error_handling = @parameters["error_handling"].to_s

    @tenant_id = @info_values["tenant_id"].to_s
    @client_id = @info_values["client_id"].to_s
    @client_secret = @info_values["client_secret"].to_s
    @api_username = @info_values["api_username"].to_s
    @api_password = @info_values["api_password"].to_s
    @kapp_slug = @info_values["kapp_slug"].to_s
    @form_slug_data = @info_values["form_slug_data"].to_s
    @form_slug_dates = @info_values["form_slug_dates"].to_s

    @from_override = @parameters["from_override"].to_s
    @from_source = @from_override.empty? ? "the handler's from_address property" : "the From (Override) input"
    @from_value = @from_override.empty? ? @info_values["from_address"].to_s : @from_override

    @template_name = @parameters["notification_template_name"].to_s
    @submission_id = @parameters["submission_id"].to_s
  end

  def execute
    error_message = nil
    @response_code = nil
    @email_id = nil
    @attachment_count = 0
    @sender = parse_address(@from_value)[:address]

    begin
      @phase = "validating the handler configuration and inputs"
      validate_configuration
      recipients = parse_recipients

      if recipients.nil?
        @status = "Skipped"
        log("The recipient has email notifications turned off; no email was sent.")
      else
        @phase = "building notification template '#{@template_name}'"
        content = build_content

        @phase = "collecting attachments"
        attachments = collect_attachments(content)

        message = build_message(content, recipients)

        @phase = "requesting an access token"
        token = fetch_access_token

        @phase = "sending the email"
        deliver(token, message, attachments)
        @status = "Sent"
        log("Email sent from #{@sender} with #{@attachment_count} attachment(s) (HTTP #{@response_code}).")
      end
    rescue HandlerError => e
      error_message = e.message
    rescue StandardError => e
      error_message = "An unexpected error occurred while #{@phase}: #{e.class}: #{e.message}"
    end

    if error_message
      @status = "Failed"
      @email_id = nil
      log(error_message)
      # Raise the error if instructed to, otherwise will fall through to
      # return an error message.
      raise error_message if @error_handling == "Raise Error"
    end

    # Return (and escape) the results that were defined in the node.xml
    <<-RESULTS
    <results>
      <result name="Handler Error Message">#{escape(error_message)}</result>
      <result name="Email Id">#{escape(@email_id)}</result>
      <result name="Status">#{escape(@status)}</result>
      <result name="From Address">#{escape(@sender)}</result>
      <result name="Attachment Count">#{escape(@attachment_count)}</result>
      <result name="Response Code">#{escape(@response_code)}</result>
    </results>
    RESULTS
  end

  ##############################################################################
  # Configuration and recipients
  ##############################################################################

  # Validates the configuration and the non-recipient inputs, collecting all of
  # the problems so they can be reported (and fixed) together.
  def validate_configuration
    problems = []

    required = ["tenant_id", "client_id", "client_secret", "api_server", "api_username", "api_password",
      "kapp_slug", "form_slug_data", "form_slug_dates"]
    missing = required.select { |name| @info_values[name].to_s.empty? }
    unless missing.empty?
      problems << "The handler configuration is missing #{join_list(missing)}. " \
        "Set #{missing.size == 1 ? "it" : "them"} in the handler's properties in Kinetic Task."
    end

    if @from_value.empty?
      problems << "No From address: set the handler's from_address property or provide a From (Override) value."
    elsif !parse_address(@from_value)[:valid]
      problems << "The From address '#{@from_value}' (from #{@from_source}) is not a valid email address."
    end

    max_size = @info_values["max_attachment_size_mb"].to_s
    if max_size.empty?
      @max_attachment_bytes = DEFAULT_MAX_ATTACHMENT_SIZE_MB * 1024 * 1024
    elsif max_size =~ /\A\d+(\.\d+)?\z/ && max_size.to_f > 0
      @max_attachment_bytes = (max_size.to_f * 1024 * 1024).to_i
    else
      problems << "The handler's max_attachment_size_mb property must be a positive number of megabytes (found '#{max_size}')."
    end

    space_slug = @parameters["space_slug"].to_s.empty? ? @info_values["space_slug"].to_s : @parameters["space_slug"].to_s
    api_server = @info_values["api_server"].to_s.sub(/\/+\z/, "")
    if !api_server.empty? && api_server !~ /\Ahttps?:\/\//i
      problems << "The handler's api_server property must start with http:// or https:// (found '#{api_server}')."
    elsif api_server.include?("${space}")
      if space_slug.empty?
        problems << "The handler's api_server property contains ${space}, but no space slug was provided " \
          "in the Space Slug input or the handler's space_slug property."
      end
      @api_server = api_server.gsub("${space}", space_slug)
    elsif !space_slug.empty?
      @api_server = "#{api_server}/#{space_slug}"
    else
      @api_server = api_server
    end

    problems << "Notification Template Name is required." if @template_name.empty?
    problems << "Recipient Json Object is required." if @parameters["recipient_json"].to_s.empty?

    raw_replacements = @parameters["replacement_values"].to_s
    if raw_replacements.empty?
      @replacement_values = {}
    else
      begin
        @replacement_values = JSON.parse(raw_replacements)
        unless @replacement_values.is_a?(Hash)
          problems << "Replacement Values must be a JSON object, for example {\"values\": {\"Field Name\": \"value\"}}."
        end
      rescue JSON::ParserError => e
        problems << "Replacement Values is not valid JSON: #{truncate(e.message, 150)}"
      end
    end

    raise HandlerError, problems.join(" ") unless problems.empty?
  end

  # Returns a Hash of "To", "CC", and "BCC" address lists, or nil when the
  # recipient has email notifications turned off.
  def parse_recipients
    raw = @parameters["recipient_json"].to_s
    parsed = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    if parsed.is_a?(Hash)
      @recipient = parsed
    elsif parsed.nil? || parsed.is_a?(String)
      # A plain address (or list of addresses) rather than a JSON object
      @recipient = { "smtpaddress" => { "to" => parsed.nil? ? raw : parsed } }
    else
      raise HandlerError, "Recipient Json Object must be a JSON object, for example " \
        "{\"smtpaddress\": {\"to\": \"user@example.com\"}}, or an email address."
    end

    if ["no", "false"].include?(@recipient["email notifications"].to_s.strip.downcase)
      return nil
    end

    smtp = @recipient["smtpaddress"]
    smtp = { "to" => smtp } if smtp.is_a?(String)
    smtp = {} unless smtp.is_a?(Hash)

    recipients = {}
    invalid = []
    [["To", "to"], ["CC", "cc"], ["BCC", "bcc"]].each do |label, key|
      value = smtp[key]
      value = value.join(",") if value.is_a?(Array)
      parsed_list = parse_address_list(value.to_s)
      recipients[label] = parsed_list.select { |address| address[:valid] }
      bad = parsed_list.reject { |address| address[:valid] }
      invalid << "#{key}: #{bad.map { |address| "'#{address[:raw]}'" }.join(", ")}" unless bad.empty?
    end

    problems = []
    problems << "Invalid email address(es) in the Recipient Json Object #{invalid.join("; ")}." unless invalid.empty?
    total = recipients.values.inject(0) { |sum, list| sum + list.size }
    if total == 0 && invalid.empty?
      problems << "The Recipient Json Object has no email addresses in smtpaddress to, cc, or bcc."
    elsif total > MAX_RECIPIENTS
      problems << "The message has #{total} recipients; Exchange Online allows at most #{MAX_RECIPIENTS} " \
        "across To, CC, and BCC. Split the recipients across multiple sends."
    end
    raise HandlerError, problems.join(" ") unless problems.empty?

    log("Recipients: #{recipients["To"].size} To, #{recipients["CC"].size} CC, #{recipients["BCC"].size} BCC.")
    recipients
  end

  ##############################################################################
  # Template content
  ##############################################################################

  def build_content
    template = find_record(@template_name)
    if template.nil?
      raise HandlerError, "No active notification template named '#{@template_name}' was found in " \
        "#{@kapp_slug}/#{@form_slug_data}. Check the Notification Template Name and that the template's Status is Active."
    end
    @template_id = template[:id]
    @template_values = template[:values]
    log("Using notification template '#{@template_name}' (submission #{@template_id}).")

    content = {}
    CONTENT_FIELDS.each { |field| content[field] = @template_values[field].to_s }

    # Snippets are expanded, then replacements applied.  This is done a second
    # time so that snippets (and replacements within them) added by replacement
    # values are also processed.
    2.times do
      expand_snippets(content)
      CONTENT_FIELDS.each { |field| content[field] = apply_replacements(content[field]) }
    end
    CONTENT_FIELDS.each { |field| content[field] = apply_dates(content[field]) }
    log_unresolved_placeholders(content)

    content["Subject"] = content["Subject"].strip
    if content["Subject"].empty?
      raise HandlerError, "Notification template '#{@template_name}' has no Subject."
    end
    if content["HTML Content"].strip.empty? && content["Text Content"].strip.empty?
      raise HandlerError, "Notification template '#{@template_name}' has no HTML Content or Text Content."
    end
    content
  end

  # Retrieves the active notification data record with the given name, choosing
  # the closest match to the recipient's language and region when there are
  # several.  Returns { :id, :values } or nil when there is no match.
  def find_record(name)
    query = %|values[Name]="#{kql_escape(name)}" AND values[Status]="Active"|
    url = "#{@api_server}/app/api/v1/kapps/#{url_encode(@kapp_slug)}/forms/#{url_encode(@form_slug_data)}" \
      "/submissions?include=values&limit=1000&q=#{url_encode(query)}"
    body = kinetic_get(url, "retrieve '#{name}' from #{@kapp_slug}/#{@form_slug_data}",
      "The kapp '#{@kapp_slug}' or form '#{@form_slug_data}' was not found. Check the handler's kapp_slug and " \
      "form_slug_data properties, and that api_server includes the space (for example https://server/kinetic/my-space).")
    records = body["submissions"].is_a?(Array) ? body["submissions"] : []
    closest_match(records)
  end

  def closest_match(records)
    return nil if records.empty?
    language = @recipient["language"].to_s
    region = @recipient["region"].to_s

    selected = records.first
    if records.size > 1 && !(language.empty? && region.empty?)
      best_score = -1
      records.each do |record|
        values = record["values"] || {}
        record_language = values["Language"].to_s
        record_region = values["Region"].to_s
        language_match = !language.empty? && language == record_language
        region_match = !region.empty? && region == record_region
        score = language_match && region_match ? 3 : language_match ? 2 : region_match ? 1 : 0
        if score > best_score
          best_score = score
          selected = record
        end
      end
    end
    { :id => selected["id"], :values => selected["values"] || {} }
  end

  def expand_snippets(content)
    @snippets ||= {}
    depth = 0
    loop do
      names = content.values.map { |value| value.scan(SNIPPET_PATTERN).flatten }.flatten.uniq
      return if names.empty?
      if depth >= MAX_SNIPPET_DEPTH
        raise HandlerError, "Snippets in notification template '#{@template_name}' are nested more than " \
          "#{MAX_SNIPPET_DEPTH} levels deep. Check for a snippet that includes itself: #{join_list(names.map { |name| "'#{name}'" })}."
      end
      depth += 1

      names.each do |name|
        snippet = (@snippets[name] ||= find_record(name))
        if snippet.nil?
          raise HandlerError, "Notification template '#{@template_name}' uses snippet '#{name}', but no active record " \
            "named '#{name}' was found in #{@kapp_slug}/#{@form_slug_data}."
        end
        tag = "${snippet('#{name}')}"
        content.keys.each do |field|
          replacement = (field == "HTML Content" ? snippet[:values]["HTML Content"] : snippet[:values]["Text Content"]).to_s
          content[field] = content[field].gsub(tag) { replacement }
        end
      end
    end
  end

  # Replaces ${key('name')} with Replacement Values[key][name].  Placeholders
  # with no matching value are left in place.
  def apply_replacements(text)
    @replacement_values.each do |key, values|
      next unless values.is_a?(Hash)
      text = text.gsub(/\$\{#{Regexp.escape(key)}\('(.*?)'\)\}/) do |match|
        values.has_key?($1) ? replacement_text(values[$1]) : match
      end
    end
    text
  end

  def replacement_text(value)
    if value.nil?
      ""
    elsif value.is_a?(String)
      value
    elsif value.is_a?(Array) && value.none? { |item| item.is_a?(Hash) || item.is_a?(Array) }
      value.join(", ")
    elsif value.is_a?(Hash) || value.is_a?(Array)
      JSON.generate(value)
    else
      value.to_s
    end
  end

  # Formats ${appearance('<date>${format('<Format Name>')}')} using the Format
  # (a strftime pattern) of the named date format record.
  def apply_dates(text)
    text.gsub(APPEARANCE_PATTERN) do
      inner = $1
      date_part, format_part = inner.split("$", 2)
      format_match = format_part.to_s.strip.match(FORMAT_PATTERN)
      unless format_match
        raise HandlerError, "The tag ${appearance('#{inner}')} in notification template '#{@template_name}' has no " \
          "${format('...')} part. Use ${appearance('<date>${format('<Format Name>')}')}."
      end

      format_name = format_match[1]
      format = date_formats[format_name]
      if format.nil?
        raise HandlerError, "Notification template '#{@template_name}' uses date format '#{format_name}', which was not " \
          "found among the active records in #{@kapp_slug}/#{@form_slug_dates}."
      end
      unless format.include?("%")
        raise HandlerError, "Date format '#{format_name}' has the Format '#{format}', which is not a strftime pattern " \
          "(for example %B %-d, %Y)."
      end

      begin
        DateTime.parse(date_part.to_s).strftime(format)
      rescue ArgumentError
        # Empty or unparseable dates are left as provided.
        date_part.to_s
      end
    end
  end

  # Name => Format for every active date format record.  Only retrieved when a
  # template uses ${appearance(...)}.
  def date_formats
    return @date_formats if @date_formats
    query = %|values[Status] IN ("active","Active")|
    url = "#{@api_server}/app/api/v1/kapps/#{url_encode(@kapp_slug)}/forms/#{url_encode(@form_slug_dates)}" \
      "/submissions?include=values&limit=1000&q=#{url_encode(query)}"
    body = kinetic_get(url, "retrieve date formats from #{@kapp_slug}/#{@form_slug_dates}",
      "The kapp '#{@kapp_slug}' or form '#{@form_slug_dates}' was not found. Check the handler's kapp_slug and " \
      "form_slug_dates properties.")
    @date_formats = {}
    (body["submissions"] || []).each do |record|
      values = record["values"] || {}
      @date_formats[values["Name"].to_s] = values["Format"].to_s
    end
    @date_formats
  end

  def log_unresolved_placeholders(content)
    return unless @debug_logging_enabled
    unresolved = content.values.map { |value| value.scan(PLACEHOLDER_PATTERN).map { |key, name| "${#{key}('#{name}')}" } }.flatten.uniq
    log("Placeholders with no replacement value (left as-is): #{unresolved.join(", ")}") unless unresolved.empty?
  end

  ##############################################################################
  # Attachments
  ##############################################################################

  # Collects the template's files, the related submission's files, and inline
  # images.  Inline image references in the HTML Content are rewritten to point
  # at the embedded images.  Returns an Array of attachment Hashes.
  def collect_attachments(content)
    files = []

    template_description = "the Template Attachments field of notification template '#{@template_name}'"
    attachment_field_files(@template_values[TEMPLATE_ATTACHMENTS_FIELD], template_description).each_with_index do |file, index|
      files << file_reference(file, @template_id, TEMPLATE_ATTACHMENTS_FIELD, index, template_description)
    end

    fields = @template_values["Attachments"].to_s.scan(ATTACHMENT_PATTERN).flatten.uniq - [TEMPLATE_ATTACHMENTS_FIELD]
    unless fields.empty?
      if @submission_id.empty?
        raise HandlerError, "Notification template '#{@template_name}' attaches files from submission " \
          "#{fields.size == 1 ? "field" : "fields"} #{join_list(fields.map { |field| "'#{field}'" })}, but no Submission Id was provided."
      end
      url = "#{@api_server}/app/api/v1/submissions/#{url_encode(@submission_id)}?include=values,form"
      submission = kinetic_get(url, "retrieve submission '#{@submission_id}'",
        "Submission '#{@submission_id}' was not found. Check the Submission Id input.")["submission"] || {}
      values = submission["values"] || {}
      form_slug = submission["form"].is_a?(Hash) ? submission["form"]["slug"] : nil

      fields.each do |field|
        unless values.has_key?(field)
          raise HandlerError, "Notification template '#{@template_name}' attaches files from field '#{field}', which " \
            "does not exist on submission '#{@submission_id}'#{form_slug ? " (form '#{form_slug}')" : ""}."
        end
        description = "field '#{field}' of submission '#{@submission_id}'"
        attachment_field_files(values[field], description).each_with_index do |file, index|
          files << file_reference(file, @submission_id, field, index, description)
        end
      end
    end

    # Check the sizes Kinetic reports before downloading anything.
    known_size = files.inject(0) { |sum, file| sum + file[:size].to_i }
    check_size_limit(files) if known_size > @max_attachment_bytes

    attachments = files.map { |file| download_attachment(file) }
    @attachment_count = attachments.size
    content["HTML Content"] = embed_inline_images(content["HTML Content"], attachments)

    check_size_limit(attachments.map { |attachment| { :name => attachment[:name], :size => attachment[:bytes].bytesize } })
    attachments.each do |attachment|
      log("#{attachment[:inline] ? "Inline image" : "Attachment"}: #{attachment[:name]} (#{format_size(attachment[:bytes].bytesize)})")
    end
    attachments
  end

  def attachment_field_files(value, description)
    return [] if value.nil? || value == "" || value == []
    if value.is_a?(String)
      value = begin
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end
    end
    unless value.is_a?(Array) && value.all? { |file| file.is_a?(Hash) && !file["name"].to_s.empty? }
      raise HandlerError, "#{sentence_case(description)} does not contain file attachments. Make sure it is an attachment field."
    end
    value
  end

  def file_reference(file, submission_id, field, index, description)
    {
      :name => file["name"].to_s,
      :size => file["size"].to_i,
      :content_type => file["contentType"].to_s,
      :submission_id => submission_id,
      :field => field,
      :index => index,
      :description => description
    }
  end

  def download_attachment(file)
    @phase = "downloading attachment '#{file[:name]}'"
    url = "#{@api_server}/app/api/v1/submissions/#{url_encode(file[:submission_id])}/files/#{url_encode(file[:field])}" \
      "/#{file[:index]}/#{url_encode(file[:name])}/url"
    link = kinetic_get(url, "get a download link for '#{file[:name]}' from #{file[:description]}",
      "The file '#{file[:name]}' was not found in #{file[:description]}.")["url"].to_s
    if link.empty?
      raise HandlerError, "The Kinetic Platform did not return a download link for '#{file[:name]}' from #{file[:description]}."
    end
    link = "#{origin(@api_server)}#{link}" if link.start_with?("/")

    response = download(link, "attachment '#{file[:name]}' from #{file[:description]}")
    content_type = file[:content_type].empty? ? media_type(response) : file[:content_type]
    { :name => file[:name], :content_type => content_type, :bytes => response.body.to_s, :inline => false }
  end

  # Downloads every http(s) image referenced as src="cid:<url>" and adds it as
  # an inline attachment, returning the HTML with the references rewritten.
  def embed_inline_images(html, attachments)
    return html if html.strip.empty?
    embedded = {}
    html.gsub(INLINE_IMAGE_PATTERN) do
      quote = $1
      url = $2
      unless embedded.has_key?(url)
        @phase = "downloading inline image #{url}"
        response = download(url, "inline image #{url} referenced in the HTML Content of notification template '#{@template_name}'")
        content_id = "image#{embedded.size + 1}.#{SecureRandom.hex(8)}@kinetic"
        attachments << {
          :name => image_name(url, embedded.size + 1),
          :content_type => media_type(response),
          :bytes => response.body.to_s,
          :inline => true,
          :content_id => content_id
        }
        embedded[url] = content_id
      end
      "#{quote}cid:#{embedded[url]}#{quote}"
    end
  end

  def check_size_limit(files)
    total = files.inject(0) { |sum, file| sum + file[:size].to_i }
    return if total <= @max_attachment_bytes
    listing = files.sort_by { |file| -file[:size].to_i }.map { |file| "#{file[:name]} (#{format_size(file[:size].to_i)})" }
    raise HandlerError, "Attachments total #{format_size(total)}, which is over the #{format_size(@max_attachment_bytes)} " \
      "limit set by the handler's max_attachment_size_mb property: #{listing.join(", ")}."
  end

  # GETs a file, following redirects.  The Kinetic API credentials are only
  # sent to the api_server host.
  def download(url, description)
    redirects = 0
    loop do
      url = url.strip.gsub(" ", "%20")
      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        raise HandlerError, "Could not download #{description}: '#{url}' is not a valid URL."
      end
      headers = {}
      headers["Authorization"] = kinetic_authorization if uri.host.to_s.downcase == URI.parse(@api_server).host.to_s.downcase
      log("Downloading #{description} from #{uri.host}")

      response = request_with_retries(:get, url, nil, headers, uri.host.to_s, :read_timeout => UPLOAD_READ_TIMEOUT)
      code = response.code.to_i
      if REDIRECT_CODES.include?(code) && !response["Location"].to_s.empty?
        if redirects >= MAX_REDIRECTS
          raise HandlerError, "Could not download #{description}: it redirected more than #{MAX_REDIRECTS} times."
        end
        redirects += 1
        url = URI.join(url, response["Location"]).to_s
        next
      end
      return response if code == 200

      hint = (code == 401 || code == 403) ? " The file may require authentication or may no longer be shared." : ""
      raise HandlerError, "Could not download #{description}: HTTP #{code} from #{uri.host}.#{hint}"
    end
  end

  ##############################################################################
  # Message building and delivery
  ##############################################################################

  def build_message(content, recipients)
    html = content["HTML Content"]
    has_html = !html.strip.empty?
    if has_html && !content["Text Content"].strip.empty?
      log("The template has both HTML Content and Text Content; sending HTML Content.")
    end

    message = {
      "subject" => content["Subject"],
      "body" => has_html ?
        { "contentType" => "HTML", "content" => html } :
        { "contentType" => "Text", "content" => content["Text Content"] }
    }
    message["toRecipients"] = recipients["To"].map { |address| to_recipient(address) } unless recipients["To"].empty?
    message["ccRecipients"] = recipients["CC"].map { |address| to_recipient(address) } unless recipients["CC"].empty?
    message["bccRecipients"] = recipients["BCC"].map { |address| to_recipient(address) } unless recipients["BCC"].empty?
    message
  end

  def deliver(token, message, attachments)
    @token = token
    @mailbox_url = "#{GRAPH_URL}/users/#{url_encode(@sender)}"

    request_size = JSON.generate(message).bytesize +
      attachments.inject(0) { |sum, attachment| sum + base64_length(attachment[:bytes].bytesize) + attachment[:name].bytesize + 300 }

    if request_size <= SINGLE_REQUEST_MAX_BYTES
      log("Sending with a single request (about #{format_size(request_size)}).")
      payload = attachments.empty? ? message : message.merge("attachments" => attachments.map { |attachment| file_attachment(attachment) })
      graph_request(:post, "#{@mailbox_url}/sendMail", JSON.generate({ "message" => payload, "saveToSentItems" => true }),
        "send the email", :sending => true)
    else
      send_with_draft(message, attachments, request_size)
    end
  end

  # Creates a draft, adds each attachment to it, and sends it.  The draft is
  # deleted if any step fails before the send.
  def send_with_draft(message, attachments, request_size)
    total = attachments.inject(0) { |sum, attachment| sum + attachment[:bytes].bytesize }
    log("Message is about #{format_size(request_size)}; sending through a draft with #{attachments.size} attachment upload(s).")
    access_denied = "The app is not allowed to create a draft in, or send mail as, #{@sender}. Emails whose " \
      "attachments are too large to send in one request (this one has #{format_size(total)} of attachments) are built " \
      "as a draft, which requires the Mail.ReadWrite application permission with admin consent in addition to " \
      "Mail.Send. Also check that no Exchange Online application access policy or RBAC for Applications scope " \
      "excludes this mailbox."

    @phase = "creating a draft message"
    response = graph_request(:post, "#{@mailbox_url}/messages", JSON.generate(message),
      "create a draft message for the attachments", :access_denied => access_denied)
    draft = parse_json(response.body) || {}
    draft_id = draft["id"].to_s
    raise HandlerError, "Microsoft Graph created a draft message but did not return its id." if draft_id.empty?
    @email_id = draft["internetMessageId"]
    draft_url = "#{@mailbox_url}/messages/#{url_encode(draft_id)}"

    begin
      attachments.each { |attachment| add_draft_attachment(draft_url, attachment, access_denied) }
      @phase = "sending the email"
      graph_request(:post, "#{draft_url}/send", "", "send the email", :sending => true, :access_denied => access_denied)
    rescue StandardError => e
      error_text = e.is_a?(HandlerError) ? e.message : "An unexpected error occurred while #{@phase}: #{e.class}: #{e.message}"
      raise HandlerError, "#{error_text}#{delete_draft(draft_url)}"
    end
  end

  def add_draft_attachment(draft_url, attachment, access_denied)
    size = attachment[:bytes].bytesize
    @phase = "uploading attachment '#{attachment[:name]}' (#{format_size(size)})"
    action = "add attachment '#{attachment[:name]}' (#{format_size(size)}) to the draft"

    if size >= UPLOAD_SESSION_MIN_BYTES
      item = {
        "attachmentType" => "file",
        "name" => attachment[:name],
        "size" => size,
        "contentType" => attachment[:content_type]
      }
      if attachment[:inline]
        item["isInline"] = true
        item["contentId"] = attachment[:content_id]
      end
      response = graph_request(:post, "#{draft_url}/attachments/createUploadSession",
        JSON.generate({ "AttachmentItem" => item }), "start the upload of attachment '#{attachment[:name]}' (#{format_size(size)})",
        :access_denied => access_denied, :pass_error_codes => ["ErrorAttachmentSizeShouldNotBeLessThanMinimumSize"])
      if response.code.to_i < 300
        upload_url = (parse_json(response.body) || {})["uploadUrl"].to_s
        if upload_url.empty?
          raise HandlerError, "Microsoft Graph did not return an upload URL for attachment '#{attachment[:name]}'."
        end
        upload_chunks(upload_url, attachment)
        return
      end
      log("Upload session refused for #{attachment[:name]} as too small; adding it with a single request.")
    end

    graph_request(:post, "#{draft_url}/attachments", JSON.generate(file_attachment(attachment)), action,
      :access_denied => access_denied)
  end

  # PUTs the attachment to the pre-authenticated upload URL in chunks.  The
  # upload URL carries its own token, so no Authorization header is sent, and
  # the URL is never logged or included in error messages.
  def upload_chunks(upload_url, attachment)
    bytes = attachment[:bytes]
    total = bytes.bytesize
    offset = 0
    max_requests = (total / UPLOAD_CHUNK_BYTES) * 2 + 5

    max_requests.times do
      chunk = bytes.byteslice(offset, UPLOAD_CHUNK_BYTES)
      last = offset + chunk.bytesize - 1
      headers = {
        "Content-Type" => "application/octet-stream",
        "Content-Range" => "bytes #{offset}-#{last}/#{total}"
      }
      log("Uploading #{attachment[:name]} bytes #{offset}-#{last} of #{total}")
      response = request_with_retries(:put, upload_url, chunk, headers, UPLOAD_LABEL, :read_timeout => UPLOAD_READ_TIMEOUT)
      code = response.code.to_i

      return if code == 201
      unless code == 200
        raise HandlerError, "Could not upload attachment '#{attachment[:name]}' (bytes #{offset}-#{last} of #{total}): " \
          "#{graph_error_message(code, response, 0, {})}"
      end

      next_ranges = (parse_json(response.body) || {})["nextExpectedRanges"]
      next_start = next_ranges.is_a?(Array) && !next_ranges.empty? ? next_ranges.first.to_s[/\A\d+/] : nil
      offset = next_start ? next_start.to_i : last + 1
      if offset >= total
        raise HandlerError, "The upload of attachment '#{attachment[:name]}' finished, but the Outlook upload service " \
          "did not confirm it (HTTP #{code})."
      end
    end
    raise HandlerError, "The upload of attachment '#{attachment[:name]}' did not complete after #{max_requests} requests."
  end

  # Removes an unsent draft and returns a sentence describing the outcome, to be
  # appended to the error message.
  def delete_draft(draft_url)
    if @send_outcome_unknown
      return " The draft was not deleted because the email may have been sent; check the Sent Items and Drafts " \
        "folders of #{@sender}."
    end
    failed_response_code = @response_code
    response = http_request(:delete, draft_url, nil, { "Authorization" => "Bearer #{@token}" }, GRAPH_LABEL)
    @response_code = failed_response_code
    if response.code.to_i < 300
      " The unsent draft was deleted from the Drafts folder of #{@sender}."
    else
      " The unsent draft could not be deleted and is still in the Drafts folder of #{@sender} (HTTP #{response.code})."
    end
  rescue HandlerError, StandardError
    @response_code = failed_response_code
    " The unsent draft could not be deleted and may still be in the Drafts folder of #{@sender}."
  end

  def file_attachment(attachment)
    json = {
      "@odata.type" => "#microsoft.graph.fileAttachment",
      "name" => attachment[:name],
      "contentType" => attachment[:content_type],
      "contentBytes" => [attachment[:bytes]].pack("m0")
    }
    if attachment[:inline]
      json["isInline"] = true
      json["contentId"] = attachment[:content_id]
    end
    json
  end

  ##############################################################################
  # Azure AD token
  ##############################################################################

  def fetch_access_token
    url = "#{AUTH_URL}/#{url_encode(@tenant_id)}/oauth2/v2.0/token"
    log("Requesting access token from #{url}")

    form = URI.encode_www_form(
      "client_id" => @client_id,
      "client_secret" => @client_secret,
      "grant_type" => "client_credentials",
      "scope" => "https://graph.microsoft.com/.default"
    )
    response = http_request(:post, url, form,
      { "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json" }, AUTH_LABEL)

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
          "and that the app is registered in this tenant."
      when "90002"
        "The tenant '#{@tenant_id}' was not found. Check the handler's tenant_id property."
      when "900023"
        "'#{@tenant_id}' is not a valid tenant identifier. Set the handler's tenant_id property to the " \
          "Directory (tenant) ID GUID or a domain such as contoso.onmicrosoft.com."
      else
        if code == 200
          "Azure AD responded but did not return an access token."
        elsif code == 400 || code == 401
          "Could not get an access token from Azure AD; the tenant_id, client_id, or client_secret property appears to be wrong."
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
  # Microsoft Graph
  ##############################################################################

  # Sends an authenticated JSON request to Graph and returns the response.  Any
  # non-2xx response is raised as a HandlerError beginning "Could not <action>",
  # unless its Graph error code is listed in options[:pass_error_codes].
  def graph_request(method, url, body, action, options = {})
    headers = {
      "Authorization" => "Bearer #{@token}",
      "Content-Type" => "application/json; charset=utf-8",
      "Accept" => "application/json"
    }
    response, retries = request_with_retries(method, url, body, headers, GRAPH_LABEL, options.merge(:return_retries => true))
    code = response.code.to_i
    log("Graph: #{action} -> HTTP #{code}")
    return response if code >= 200 && code < 300

    error = (parse_json(response.body) || {})["error"]
    graph_code = error.is_a?(Hash) ? error["code"].to_s : ""
    return response if Array(options[:pass_error_codes]).include?(graph_code)

    raise HandlerError, "Could not #{action}: #{graph_error_message(code, response, retries, options)}"
  end

  def graph_error_message(code, response, retries, options)
    body = parse_json(response.body)
    error = (body.is_a?(Hash) && body["error"].is_a?(Hash)) ? body["error"] : {}
    graph_code = error["code"].to_s
    graph_message = error["message"].to_s
    inner_error = error["innerError"].is_a?(Hash) ? error["innerError"] : {}
    request_id = response["request-id"] || inner_error["request-id"]
    retried = retries > 0 ? " (after #{retries} #{retries == 1 ? "retry" : "retries"})" : ""

    access_denied = options[:access_denied] || "The app is not allowed to send mail as #{@sender}. Make sure the " \
      "app registration has the Mail.Send application permission with admin consent granted, and that no Exchange " \
      "Online application access policy or RBAC for Applications scope excludes this mailbox."
    not_found = "The sender mailbox #{@sender} was not found. It must be an Exchange Online user or shared " \
      "mailbox in this tenant."
    too_large = "The message is larger than the sender mailbox's maximum send size. Exchange Online's default is " \
      "35 MB, and attachments grow by about a third when sent. Lower the handler's max_attachment_size_mb property " \
      "or ask an Exchange administrator to raise the mailbox's MaxSendSize."

    friendly =
      case graph_code
      when "ErrorAccessDenied", "ErrorSendAsDenied", "Authorization_RequestDenied", "AccessDenied"
        access_denied
      when "ErrorInvalidUser", "ResourceNotFound", "Request_ResourceNotFound", "ErrorNonExistentMailbox"
        not_found
      when "ErrorItemNotFound"
        "The draft message was not found in the mailbox of #{@sender}; it may have been deleted while the email was being built."
      when "MailboxNotEnabledForRESTAPI", "MailboxNotSupportedForRESTAPI"
        "The sender mailbox #{@sender} cannot be used with Microsoft Graph. It may be inactive, unlicensed, " \
          "soft-deleted, or hosted on-premises."
      when "ErrorInvalidRecipients"
        "Exchange Online rejected one or more recipients. Check the addresses in the Recipient Json Object."
      when "ErrorMessageSizeExceeded", "RequestEntityTooLarge", "ErrorAttachmentSizeLimitExceeded"
        too_large
      when "ErrorExceededMessageLimit", "ErrorQuotaExceeded"
        "The sender mailbox #{@sender} has reached an Exchange Online sending limit. Try again later or use a different sender."
      when "InvalidAuthenticationToken"
        "Microsoft Graph rejected the access token. Check that the app registration belongs to tenant '#{@tenant_id}'."
      else
        if code == 400
          "Microsoft Graph rejected the request as invalid."
        elsif code == 401
          "Microsoft Graph rejected the access token. Check that the app registration belongs to tenant '#{@tenant_id}'."
        elsif code == 403
          access_denied
        elsif code == 404
          not_found
        elsif code == 413
          too_large
        elsif code == 429
          "Microsoft Graph is throttling requests for this app or mailbox#{retried}. Try again later."
        elsif code == 503
          "Microsoft Graph is temporarily unavailable#{retried}. Try again later."
        elsif code >= 500
          if options[:sending]
            "Microsoft Graph returned a server error. The email may or may not have been sent; check the Sent " \
              "Items folder of #{@sender} before trying again."
          else
            "Microsoft Graph returned a server error. Try again later."
          end
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
  # Kinetic Platform API
  ##############################################################################

  # GETs a Kinetic Platform API url and returns the parsed JSON body.
  # +action+ completes the sentence "while trying to ..." and +not_found+ is
  # the message used for a 404.
  def kinetic_get(url, action, not_found)
    headers = { "Authorization" => kinetic_authorization, "Accept" => "application/json" }
    response = request_with_retries(:get, url, nil, headers, kinetic_label)
    code = response.code.to_i
    body = parse_json(response.body)
    log("Kinetic: #{action} -> HTTP #{code}")

    if code == 200
      return body if body.is_a?(Hash)
      raise HandlerError, "The Kinetic Platform API at #{@api_server} returned a response that is not JSON while " \
        "trying to #{action}. Check the handler's api_server property (for example https://my-space.kinops.io or " \
        "https://server/kinetic/my-space)."
    end

    friendly =
      if code == 401
        "The Kinetic Platform rejected the handler's api_username and api_password while trying to #{action}."
      elsif code == 403
        "The Kinetic API user '#{@api_username}' is not allowed to #{action}. Check the user's access to the space, kapp, and form."
      elsif code == 404
        not_found
      elsif code >= 500
        "The Kinetic Platform returned a server error while trying to #{action}. Try again later."
      else
        "The Kinetic Platform could not #{action}."
      end

    details = []
    kinetic_message = body.is_a?(Hash) ? (body["error"] || body["message"]).to_s : ""
    if !kinetic_message.empty?
      details << "Kinetic: #{kinetic_message}"
    elsif !response.body.to_s.strip.empty?
      details << "Response: #{truncate(response.body)}"
    end
    details << "HTTP #{code}"
    raise HandlerError, "#{friendly} (#{details.join("; ")})"
  end

  def kinetic_authorization
    "Basic #{["#{@api_username}:#{@api_password}"].pack("m0")}"
  end

  def kinetic_label
    "the Kinetic Platform API (#{URI.parse(@api_server).host})"
  end

  ##############################################################################
  # HTTP
  ##############################################################################

  # Sends the request, retrying responses with RETRY_CODES and honoring
  # Retry-After.  Returns the response, or [response, retries] when
  # options[:return_retries] is set.
  def request_with_retries(method, url, body, headers, label, options = {})
    retries = 0
    loop do
      response = http_request(method, url, body, headers, label, options)
      code = response.code.to_i
      if RETRY_CODES.include?(code) && retries < MAX_RETRIES
        retries += 1
        wait = retry_wait_seconds(response, retries)
        log("#{label} returned HTTP #{code}; retry #{retries} of #{MAX_RETRIES} in #{wait} seconds.")
        sleep(wait)
        next
      end
      return options[:return_retries] ? [response, retries] : response
    end
  end

  def retry_wait_seconds(response, retries)
    retry_after = Integer(response["Retry-After"].to_s) rescue nil
    wait = (retry_after && retry_after > 0) ? retry_after : 2 ** retries
    [wait, MAX_RETRY_WAIT].min
  end

  # Sends a single request and returns the Net::HTTPResponse for any HTTP
  # status.  Network level failures are translated into a HandlerError.
  # options[:sending] indicates the request sends the email, where a failure
  # after the request was written means the email may already have been sent.
  def http_request(method, url, body, headers, label, options = {})
    @response_code = nil
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = options[:read_timeout] || READ_TIMEOUT

    request_class = {
      :get => Net::HTTP::Get,
      :post => Net::HTTP::Post,
      :put => Net::HTTP::Put,
      :delete => Net::HTTP::Delete
    }[method]
    request = request_class.new(uri.request_uri)
    headers.each { |name, value| request[name] = value }
    request.body = body unless body.nil?

    response = http.request(request)
    @response_code = response.code.to_i
    response
  rescue Timeout::Error => e
    if defined?(Net::OpenTimeout) && e.is_a?(Net::OpenTimeout)
      raise HandlerError, "Timed out after #{OPEN_TIMEOUT} seconds connecting to #{label}. Check network " \
        "connectivity and any proxy or firewall rules between Kinetic Task and #{label}."
    elsif options[:sending]
      @send_outcome_unknown = true
      raise HandlerError, "Timed out waiting for Microsoft Graph to respond. The email may or may not have been " \
        "sent; check the Sent Items folder of #{@sender} before trying again."
    else
      raise HandlerError, "Timed out waiting for a response from #{label}. Try again later."
    end
  rescue SocketError => e
    raise HandlerError, "Could not connect to #{label}: #{e.message}. Check DNS and network connectivity " \
      "from the Kinetic Task server."
  rescue OpenSSL::SSL::SSLError => e
    raise HandlerError, "Could not establish a secure (TLS) connection to #{label}: #{e.message}. A proxy " \
      "that intercepts TLS traffic or an outdated certificate store is a common cause."
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT => e
    raise HandlerError, "Could not connect to #{label}: #{e.message}. Check network connectivity and any " \
      "proxy or firewall rules between Kinetic Task and #{label}."
  rescue Errno::ECONNRESET, Errno::EPIPE, EOFError => e
    message = "The connection to #{label} was interrupted: #{e.message}."
    if options[:sending]
      @send_outcome_unknown = true
      message << " The email may or may not have been sent; check the Sent Items folder of #{@sender} before trying again."
    end
    raise HandlerError, message
  end

  ##############################################################################
  # Addresses
  ##############################################################################

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
  # General handler utility functions
  ##############################################################################

  def parse_json(string)
    JSON.parse(string.to_s)
  rescue JSON::ParserError
    nil
  end

  def url_encode(value)
    ERB::Util.url_encode(value.to_s)
  end

  def kql_escape(value)
    value.to_s.gsub(/["\\]/) { |char| "\\#{char}" }
  end

  def origin(url)
    uri = URI.parse(url)
    default_port = (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "http" && uri.port == 80)
    "#{uri.scheme}://#{uri.host}#{default_port ? "" : ":#{uri.port}"}"
  end

  def media_type(response)
    type = response["Content-Type"].to_s.split(";").first.to_s.strip
    type.empty? ? "application/octet-stream" : type
  end

  def image_name(url, number)
    name = File.basename(URI.parse(url).path.to_s) rescue ""
    name.to_s.empty? || name == "/" ? "image#{number}" : name
  end

  def base64_length(bytes)
    ((bytes + 2) / 3) * 4
  end

  def format_size(bytes)
    if bytes < 1024 * 1024
      "#{(bytes / 1024.0).ceil} KB"
    else
      "#{format("%.1f", bytes / (1024.0 * 1024.0)).sub(/\.0\z/, "")} MB"
    end
  end

  def join_list(items)
    items.size <= 1 ? items.join : "#{items[0..-2].join(", ")} and #{items[-1]}"
  end

  def sentence_case(text)
    text.empty? ? text : "#{text[0, 1].upcase}#{text[1..-1]}"
  end

  def truncate(string, length = 300)
    value = string.to_s.strip.gsub(/\s+/, " ")
    value.length > length ? "#{value[0, length]}..." : value
  end

  # Never pass the client secret, access tokens, upload URLs, recipient
  # addresses, or body content to this method.
  def log(message)
    puts "[azure_notification_template_send_v1] #{message}" if @debug_logging_enabled
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
