# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class AzureVmShutdownV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'

    # Store parameters values in a Hash of parameter names to values.
    @parameters = {}
    REXML::XPath.match(@input_document, '/handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end

  def execute()
    resources_path = File.join(File.expand_path(File.dirname(__FILE__)), 'resources')
    cert_location = resources_path + "/" + "mycert.pem"
    key_location = resources_path + "/" + "mycert-key.pem"

    subscription_id = @parameters['subscription_id']
    vm_name = @parameters['vm_name']

    resource = RestClient::Resource.new("https://management.core.windows.net", 
      :ssl_client_cert => OpenSSL::X509::Certificate.new(File.read(cert_location)),
      :ssl_client_key => OpenSSL::PKey::RSA.new(File.read(key_location)),
      :headers => {"x-ms-version" => "2015-04-01", :accept => "application/json"})

    begin
      resp = resource["#{subscription_id}/services/hostedservices/#{vm_name}?embed-detail=true"].get
    rescue Exception => e
      raise e.inspect
    end

    doc = REXML::Document.new(resp)
    deployment_name = REXML::XPath.match(doc, '/HostedService/Deployments/Deployment/Name').first.text
    role_name = REXML::XPath.match(doc, '/HostedService/Deployments/Deployment/RoleInstanceList/RoleInstance/InstanceName').first.text

    restart_xml = <<-XML
<ShutdownRoleOperation xmlns="http://schemas.microsoft.com/windowsazure" xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
  <OperationType>ShutdownRoleOperation</OperationType>
</ShutdownRoleOperation>
XML

    resource.headers["Content-Type"] = "application/xml"
    begin
      resp = resource["#{subscription_id}/services/hostedservices/#{vm_name}/deployments/#{deployment_name}/roleinstances/#{role_name}/Operations"].post restart_xml.strip
    rescue Exception => e
      raise e.inspect
    end

    "<results/>"
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