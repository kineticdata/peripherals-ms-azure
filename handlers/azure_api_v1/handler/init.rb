# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class AzureApiV1
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

    @debug_logging_enabled = ["yes","true"].include?(@info_values['enable_debug_logging'].downcase)
    @error_handling = @parameters["error_handling"]

    @tenent_id = @info_values["tenent_id"]
    @client_id = @info_values["client_id"]
    @client_secret = @info_values["client_secret"]
    
    @headers = @parameters["headers"].to_s.empty? ? {} : JSON.parse(@parameters["headers"])
    @body = @parameters["body"].to_s.empty? ? {} : JSON.parse(@parameters["body"])
    @method = (@parameters["method"] || :get).downcase.to_sym
    @path = @parameters["path"]
    @path = "/#{@path}" if !@path.start_with?("/")

    @accept = :json
    @content_type = :json
  end

  def execute
    # Initialize return data
    error_message = nil
    error_key = nil
    response_code = nil
    max_retries = 5
    retries = 0

    begin
      auth_url = "https://login.microsoftonline.com/#{@tenent_id}/oauth2/v2.0/token"
      asset_url = "https://graph.microsoft.com/v1.0#{@path}"
      puts "AUTH URL: #{auth_url}" if @debug_logging_enabled
      puts "ASSET URL: #{asset_url}" if @debug_logging_enabled
      puts "BODY: #{@body}" if @debug_logging_enabled

      auth_response = RestClient::Request.execute \
        method: 'POST', \
        url: auth_url, \
        payload: {
          "client_id" => @client_id,
          "client_secret" => @client_secret,
          "grant_type" => "client_credentials",
          "scope" => "https://graph.microsoft.com/.default"
        }, \
        headers: {:content_type => 'application/x-www-form-urlencoded', :accept => @accept}
      token = JSON.parse(auth_response.body)['access_token']
      response = RestClient::Request.execute \
        method: @method, \
        url: asset_url, \
        payload: @body.to_json, \
        headers: {
          :content_type => @content_type, 
          :accept => @accept,
          :Authorization => token
      }.merge(@headers)

      response_code = response.code

    rescue RestClient::Exception => e
      error = nil
      response_code = e.response.code
      error_message = e.inspect
      puts error_message if @debug_logging_enabled
      # Raise the error if instructed to, otherwise will fall through to
      # return an error message.
      raise if @error_handling == "Raise Error"
    end

    # Return (and escape) the results that were defined in the node.xml
    <<-RESULTS
    <results>
      <result name="Response Body">#{escape(response.nil? ? {} : response.body)}</result>
      <result name="Response Code">#{escape(response_code)}</result>
      <result name="Handler Error Message">#{escape(error_message)}</result>
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
end
