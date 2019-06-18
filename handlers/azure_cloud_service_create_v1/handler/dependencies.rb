# If the Kinetic Task version is under 4, load the openssl and json libraries
# because they are not included in the ruby version
if KineticTask::VERSION.split('.').first.to_i < 4
    # Load the JRuby Open SSL library unless it has already been loaded.  This
    # prevents multiple handlers using the same library from causing problems.
    if not defined?(Jopenssl)
      # Load the Bouncy Castle library unless it has already been loaded.  This
      # prevents multiple handlers using the same library from causing problems.
      # Calculate the location of this file
      handler_path = File.expand_path(File.dirname(__FILE__))
      # Calculate the location of our library and add it to the Ruby load path
      library_path = File.join(handler_path, 'vendor/bouncy-castle-java-1.5.0147/lib')
      $:.unshift library_path
      # Require the library
      require 'bouncy-castle-java'
      
      
      # Calculate the location of this file
      handler_path = File.expand_path(File.dirname(__FILE__))
      # Calculate the location of our library and add it to the Ruby load path
      library_path = File.join(handler_path, 'vendor/jruby-openssl-0.8.8/lib/shared')
      $:.unshift library_path
      # Require the library
      require 'openssl'
      # Require the version constant
      require 'jopenssl/version'
    end

    # Validate the the loaded openssl library is the library that is expected for
    # this handler to execute properly.
    if not defined?(Jopenssl::Version::VERSION)
      raise "The Jopenssl class does not define the expected VERSION constant."
    elsif Jopenssl::Version::VERSION != '0.8.8'
      raise "Incompatible library version #{Jopenssl::Version::VERSION} for Jopenssl.  Expecting version 0.8.8"
    end




    # Load the ruby JSON library unless it has already been loaded.  This prevents
    # multiple handlers using the same library from causing problems.
    if not defined?(JSON)
      # Calculate the location of this file
      handler_path = File.expand_path(File.dirname(__FILE__))
      # Calculate the location of our library and add it to the Ruby load path
      library_path = File.join(handler_path, 'vendor/json-1.8.0/lib')
      $:.unshift library_path
      # Require the library
      require 'json'
    end

    # Validate the the loaded JSON library is the library that is expected for
    # this handler to execute properly.
    if not defined?(JSON::VERSION)
      raise "The JSON class does not define the expected VERSION constant."
    elsif JSON::VERSION != '1.8.0'
      raise "Incompatible library version #{JSON::VERSION} for JSON.  Expecting version 1.8.0."
    end
end

# Load the ruby Mime Types library unless it has already been loaded.  This prevents
# multiple handlers using the same library from causing problems.
if not defined?(MIME)
  # Calculate the location of this file
  handler_path = File.expand_path(File.dirname(__FILE__))
  # Calculate the location of our library and add it to the Ruby load path
  library_path = File.join(handler_path, 'vendor/mime-types-1.19/lib/')
  $:.unshift library_path
  # Require the library
  require 'mime/types'
end

# Validate the the loaded Mime Types library is the library that is expected for
# this handler to execute properly.
if not defined?(MIME::Types::VERSION)
  raise "The Mime class does not define the expected VERSION constant."
elsif MIME::Types::VERSION != '1.19'
  raise "Incompatible library version #{MIME::Types::VERSION} for Mime Types.  Expecting version 1.19."
end


# Load the ruby Rest Client library unless it has already been loaded.  This prevents
# multiple handlers using the same library from causing problems.
if not defined?(RestClient)
  # Calculate the location of this file
  handler_path = File.expand_path(File.dirname(__FILE__))
  # Calculate the location of our library and add it to the Ruby load path
  library_path = File.join(handler_path, 'vendor/rest-client-1.6.7/lib/')
  $:.unshift library_path
  # Require the library
  require 'restclient'
end

# Validate the the loaded Rest Client library is the library that is expected for
# this handler to execute properly.
if not defined?(RestClient.version)
  raise "The Rest Client class does not define the expected VERSION constant."
elsif RestClient.version != '1.6.7'
  raise "Incompatible library version #{RestClient.version} for Rest Client.  Expecting version 1.6.7."
end

# Load the ruby SafeYAML library unless it has already been loaded.  This prevents
# multiple handlers using the same library from causing problems.
if not defined?(SafeYAML)
  # Calculate the location of this file
  handler_path = File.expand_path(File.dirname(__FILE__))
  # Calculate the location of our library and add it to the Ruby load path
  library_path = File.join(handler_path, 'vendor/safe_yaml-1.0.4/lib/')
  $:.unshift library_path
  # Require the library
  require 'safe_yaml'
  require 'safe_yaml/version'
end

# Validate the the loaded Rest Client library is the library that is expected for
# this handler to execute properly.
if not defined?(SafeYAML::VERSION)
  raise "The Rest Client class does not define the expected VERSION constant."
elsif SafeYAML::VERSION != '1.0.4'
  raise "Incompatible library version #{SafeYAML::VERSION} for SafeYAML.  Expecting version 1.0.4."
end

# Load the ruby Crack library unless it has already been loaded.  This prevents
# multiple handlers using the same library from causing problems.
if not defined?(Crack)
  # Calculate the location of this file
  handler_path = File.expand_path(File.dirname(__FILE__))
  # Calculate the location of our library and add it to the Ruby load path
  library_path = File.join(handler_path, 'vendor/crack-0.4.3/lib/')
  $:.unshift library_path
  # Require the library
  require 'crack'
  require 'crack/version'
end

# Validate the the loaded Rest Client library is the library that is expected for
# this handler to execute properly.
if not defined?(Crack::VERSION)
  raise "The Crack class does not define the expected VERSION constant."
elsif Crack::VERSION != '0.4.3'
  raise "Incompatible library version #{Crack::VERSION} for Crack.  Expecting version 0.4.3."
end