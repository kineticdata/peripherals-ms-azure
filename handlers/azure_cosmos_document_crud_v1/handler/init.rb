# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class AzureCosmosDocumentCrudV1
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

    @enable_debug_logging = @info_values['enable_debug_logging'].downcase == 'yes' ||
                            @info_values['enable_debug_logging'].downcase == 'true'
    puts "Parameters: #{@parameters.inspect}" if @enable_debug_logging
  end

  def execute
    error_handling  = @parameters["error_handling"]
    error_message = nil
    method = @parameters["method"].downcase
    partition_keys = @parameters["partition_key"].split(",")

    begin

      time_gmt_now = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S GMT");
      puts "GMT used: #{time_gmt_now}" if @enable_debug_logging

      resource_id = "dbs/#{@parameters["database_name"]}/colls/#{@parameters["collection_name"]}"
      if (method == 'put' || method == 'delete')
        resource_id += "/docs/#{@parameters["document_name"]}"
      end
      puts "Resource Id: #{resource_id}" if @enable_debug_logging
      auth_token = build_authorization(method, resource_id, time_gmt_now, @info_values["master_key"])

      api_route = "#{@info_values["origin"]}/#{resource_id}"
      if (method != 'put' && method != 'delete')
        api_route += "/docs"
      end
      puts "API ROUTE: #{api_route}" if @enable_debug_logging

      headers = build_headers(method, partition_keys, time_gmt_now, auth_token)
      puts "Headers: #{headers.inspect}" if @enable_debug_logging

      request_hash = {
        method: method,
        url: api_route, 
        headers: headers
      }

      if (method == 'post' || method == 'put')
        request_hash[:payload] = @parameters["body"]
      end

      resource = RestClient::Request.new(request_hash).execute()
    rescue RestClient::Exception => error
      error_message = "#{error.http_code}: #{JSON.parse(error.response)}"
      raise error_message if error_handling == "Raise Error"
    rescue Exception => error
      error_message = error.inspect
      raise error if error_handling == "Raise Error"
    end

    # Build the results to be returned by this handler
    return <<-RESULTS
    <results>
      <result name="Handler Error Message">#{escape(error_message)}</result>
      <result name="output">#{escape(resource)}</result>
    </results>
    RESULTS
  end


  ##############################################################################
  # General handler utility functions
  ##############################################################################

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

  # Cosmos requires a special authorization token that is made up of the Rest method
  # resource type (in this case we hard code docs), the resource link (the path to 
  # the asset), a date in GMT (which must also be included in the header), and the
  # master key for the Cosmos DB account. For more info visit:
  # https://docs.microsoft.com/en-us/rest/api/cosmos-db/access-control-on-cosmosdb-resources
  def build_authorization(verb, resource_id, date, master_key)
    text = "#{(verb || "").downcase}\ndocs\n#{(resource_id || "")}\n#{date.downcase}\n\n"

    key = Base64.urlsafe_decode64 master_key
    hmac = OpenSSL::HMAC.digest 'sha256', key, text
    signature = Base64.encode64(hmac).strip

    return ERB::Util.url_encode "type=master&ver=1.0&sig=#{signature}"
  end

  # Because this handler is multipurpose different headers are required depending
  # on the desired funtionality
  def build_headers(method, partition_keys, time_gmt_now, auth_token)
    headers = Hash.new
    headers["x-ms-date"] = time_gmt_now
    headers["authorization"] = auth_token
    headers["x-ms-version"] = '2018-12-31'
    headers["Content-Type"] = "application/json" 

    if (method == 'post' && partition_keys.length <= 0)
      headers["Content-Type"] = "application/query+json"
      headers["x-ms-documentdb-isquery"] = "True"
      headers["x-ms-documentdb-query-enablecrosspartition"] = "True"
    elsif ((method == 'post' || method == 'put' || method='delete') && partition_keys.length > 0)
      headers["x-ms-documentdb-partitionkey"] = partition_keys
    end

    return headers
  end
end
