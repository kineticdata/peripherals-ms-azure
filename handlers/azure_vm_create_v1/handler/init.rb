# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class AzureVmCreateV1
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

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end
  end

  def execute
    server                    = @info_values["server"]
    subscription_id           = @parameters["subscription_id"]
    vm_name                   = @parameters["vm_name"]
    vm_label                  = Base64.encode64(vm_name)
    vm_user                   = @parameters["vm_user"]
    password                  = @parameters["password"]
    os_type                   = @parameters["os_type"]
    image                     = @parameters["image"]
    location                  = @parameters["location"]
    cloud_service_name        = @parameters["cloud_service_name"]
    vm_size                   = @parameters["vm_size"]
    affinity_group_name       = @parameters["affinity_group_name"]
    virtual_network_name      = @parameters["virtual_network_name"]
    subnet_name               = @parameters["subnet_name"]
    availability_set_name     = @parameters["availability_set_name"]
    endpoints                 = @parameters["endpoints"]

    resources_path  = File.join(File.expand_path(File.dirname(__FILE__)), "resources")
    cert_location   = "#{resources_path}/cert.pem"
    key_location    = "#{resources_path}/cert.key"

    # If creating a Windows machine, these parameters are required.
    windows_params = if os_type == "Windows"
      "<ComputerName>#{vm_name}</ComputerName>
       <AdminPassword>#{password}</AdminPassword>
       <AdminUsername>#{vm_user}</AdminUsername>"
    end
    
    # Create VM
    resource = RestClient::Resource.new("#{server}/#{subscription_id}/services/hostedservices/#{cloud_service_name}/deployments",
      :ssl_client_cert  => OpenSSL::X509::Certificate.new(File.read(cert_location)),
      :ssl_client_key   => OpenSSL::PKey::RSA.new(File.read(key_location)),
      :headers          => {"x-ms-version" => "2015-04-01", :accept => "application/json", :content_type => "xml"}
    )

    vm_body = "<?xml version=\"1.0\"?>
    <Deployment xmlns=\"http://schemas.microsoft.com/windowsazure\" xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">
      <Name>#{cloud_service_name}</Name>
      <DeploymentSlot>Production</DeploymentSlot>
      <Label>#{vm_label}</Label>
      <RoleList>
        <Role i:type=\"PersistentVMRole\">
          <RoleName>#{vm_name}</RoleName>
          <OsVersion i:nil=\"true\"/>
          <RoleType>PersistentVMRole</RoleType>
          <ConfigurationSets>
            <ConfigurationSet i:type=\"#{os_type}ProvisioningConfigurationSet\">
              #{windows_params}
              <ConfigurationSetType>#{os_type}ProvisioningConfiguration</ConfigurationSetType>
              <HostName>#{vm_name}</HostName>
              <UserName>#{vm_user}</UserName>
              <UserPassword>#{password}</UserPassword>
              <DisableSshPasswordAuthentication>false</DisableSshPasswordAuthentication>
            </ConfigurationSet>
            <ConfigurationSet i:type=\"NetworkConfigurationSet\">
              <ConfigurationSetType>NetworkConfiguration</ConfigurationSetType>
              <InputEndpoints>
                #{endpoints}
              </InputEndpoints>
              <SubnetNames>
                <SubnetName>#{subnet_name}</SubnetName>
              </SubnetNames>
            </ConfigurationSet>
          </ConfigurationSets>
          <AvailabilitySetName>#{availability_set_name}</AvailabilitySetName>
          <Label>#{vm_label}</Label>
          <OSVirtualHardDisk>
            <SourceImageName>#{image}</SourceImageName>
          </OSVirtualHardDisk>
          <RoleSize>#{vm_size}</RoleSize>
        </Role>
      </RoleList>
      <VirtualNetworkName>#{virtual_network_name}</VirtualNetworkName>
    </Deployment>"

    response = resource.post(vm_body)

    <<-RESULTS
    <results>
      <result name="request_id">#{escape(response.headers[:x_ms_request_id])}</result>
    </results>
    RESULTS

    rescue RestClient::Exception => error
      if error.http_code == 409
        # If deployment already exists, create the VM for the deployment.
        begin
          resource = RestClient::Resource.new("#{server}/#{subscription_id}/services/hostedservices/#{cloud_service_name}/deployments/#{cloud_service_name}/roles",
            :ssl_client_cert  => OpenSSL::X509::Certificate.new(File.read(cert_location)),
            :ssl_client_key   => OpenSSL::PKey::RSA.new(File.read(key_location)),
            :headers          => {"x-ms-version" => "2015-04-01", :accept => "application/json", :content_type => "xml"}
          )

          body = "<?xml version=\"1.0\"?>
          <PersistentVMRole xmlns=\"http://schemas.microsoft.com/windowsazure\" xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">
            <RoleName>#{vm_name}</RoleName>
            <RoleType>PersistentVMRole</RoleType>
            <ConfigurationSets>
              <ConfigurationSet i:type=\"#{os_type}ProvisioningConfigurationSet\">
                #{windows_params}
                <ConfigurationSetType>#{os_type}ProvisioningConfiguration</ConfigurationSetType>
                <HostName>#{vm_name}</HostName>
                <UserName>#{vm_user}</UserName>
                <UserPassword>#{password}</UserPassword>
                <DisableSshPasswordAuthentication>false</DisableSshPasswordAuthentication>
              </ConfigurationSet>
              <ConfigurationSet i:type=\"NetworkConfigurationSet\">
                <ConfigurationSetType>NetworkConfiguration</ConfigurationSetType>
                <InputEndpoints>
                  #{endpoints}
                </InputEndpoints>
                <SubnetNames>
                  <SubnetName>#{subnet_name}</SubnetName>
                </SubnetNames>
              </ConfigurationSet>
            </ConfigurationSets>
            <AvailabilitySetName>#{availability_set_name}</AvailabilitySetName>
            <Label>#{vm_label}</Label>
            <OSVirtualHardDisk>
              <SourceImageName>#{image}</SourceImageName>
            </OSVirtualHardDisk>
            <RoleSize>#{vm_size}</RoleSize>
          </PersistentVMRole>"
          
          response = resource.post(body)

          <<-RESULTS
          <results>
            <result name="request_id">#{escape(response.headers[:x_ms_request_id])}</result>
          </results>
          RESULTS

        rescue RestClient::Exception => error
          raise StandardError, error.response
        end
      else
        raise StandardError, error.response
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