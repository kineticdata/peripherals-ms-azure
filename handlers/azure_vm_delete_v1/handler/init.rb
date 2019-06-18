# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class AzureVmDeleteV1
  # Prepare for execution by building Hash objects for necessary values and
  # validating the present state.  This method sets the following instance
  # variables:
  # * @input_document - A REXML::Document object that represents the input Xml.
  # * @info_values - A Hash of info names to info values.
  # * @parameters - A Hash of parameter names to parameter values.
  #
  # This is a required method that is automatically called by the Kinetic Task
  # Engine.
  #
  # ==== Parameters
  # * +input+ - The String of Xml that was built by evaluating the node.xml
  #   handler template.
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    @enable_debug_logging = @info_values["enable_debug_logging"] == "Yes"

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end
  end

  def execute
    server              = @info_values["server"]
    subscription_id     = @parameters["subscription_id"]
    cloud_service_name  = @parameters["cloud_service_name"]
    disk_name           = @parameters["disk_name"]
    vm_deployment       = @parameters["vm_deployment"]
    vm_name             = @parameters["vm_name"]
    delete_disk         = "comp=media" if @parameters["delete_disk"] == "Yes"

    resources_path      = File.join(File.expand_path(File.dirname(__FILE__)), "resources")
    cert_location       = "#{resources_path}/cert.pem"
    key_location        = "#{resources_path}/cert.key"

    resource = RestClient::Resource.new("#{server}/#{subscription_id}/services/hostedservices/#{cloud_service_name}/deployments/#{vm_deployment}/roles/#{vm_name}?#{delete_disk}",
      :ssl_client_cert  => OpenSSL::X509::Certificate.new(File.read(cert_location)),
      :ssl_client_key   => OpenSSL::PKey::RSA.new(File.read(key_location)),
      :headers          => { "x-ms-version" => "2015-04-01", :accept => "application/json", :content_type => "xml"},
    )
    
    response = resource.delete
    
    <<-RESULTS
    <results>
      <result name="request_id">#{escape(response.headers[:x_ms_request_id])}</result>
    </results>
    RESULTS

    rescue RestClient::Exception => error
      if error.http_code == 400
        begin
          resource = RestClient::Resource.new("#{server}/#{subscription_id}/services/hostedservices/#{cloud_service_name}/deployments/#{vm_deployment}?#{delete_disk}",
            :ssl_client_cert  => OpenSSL::X509::Certificate.new(File.read(cert_location)),
            :ssl_client_key   => OpenSSL::PKey::RSA.new(File.read(key_location)),
            :headers          => { "x-ms-version" => "2015-04-01", :accept => "application/json", :content_type => "xml"}
          )

          response = resource.delete

          <<-RESULTS
          <results>
            <result name="request_id">#{escape(response.headers[:x_ms_request_id])}</result>
          </results>
          RESULTS
        rescue RestClient::Exception => error
          raise StandardError, error
        end
      else
        raise StandardError, error
      end
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