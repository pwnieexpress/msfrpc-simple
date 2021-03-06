$:.unshift(File.expand_path(File.dirname(__FILE__)))
require 'msfrpc-client'
require 'features/framework'
require 'features/pro'
require 'module_mapper'
require 'timeout'
require 'logger'

module Msf
  module RPC
    module Simple
      class Client

        include Msf::RPC::Simple::Features::Framework
        include Msf::RPC::Simple::Features::Pro

        # Public: Create a simple client object.
        #
        # user_options - hash of options to include in our initial connection.
        # project - project name we want to use for this connection.
        #
        # Returns nothing.
        def initialize(user_options)

          # configure default options
          @options = {
            :project => user_options[:project] || "default",
            :port => user_options[:port] || 55553,
            :user => user_options[:rpc_user],
            :pass => user_options[:rpc_pass],
            :db_host => user_options[:db_host] || "localhost",
            :db_user => user_options[:db_user],
            :db_pass => user_options[:db_pass],
            :db_name => user_options[:db_name] || "msf"
          }

          @options.merge!(user_options)

          #
          # Connect to the RPC daemon using the default client
          #
          @client = Msf::RPC::Client.new(@options)

          # connect to the database 
          _connect_database
        end

        # Public: clean up after ourselves 
        #
        # Returns nothing
        def cleanup
          _send_command("hosts -d")
          _send_command("services -d")
          _send_command("creds -d")
        end

        # Public: list all running threads
        #
        # Returns a hash of running threads
        def list_threads
          @client.call("core.thread_list")
        end

        # Public: determine if we're connected to the RPC server
        #
        # returns true/false
        def rpc_connected?
          return false unless @client.call("core.version")
        true
        end
        
        # Public: determine if we're connected to the RPC server
        #
        # returns true/false
        def db_connected?
          return false unless _send_command("db_status") =~ /connected/
        true
        end

        # Public: Creates and retuns an xml report
        #
        # This method is ugly for a number of reasons, but there doesn't
        # appear to be a way to be notified when the command is completed
        #
        # returns a valid xml string
        def create_report
          report_path = "/tmp/metasploit_#{@workspace_name}.xml"

          # Create the report using the db_export command
          _send_command("db_export #{report_path}\n")

          # We've sent the command, so let's sit back and wait for th
          # output to hit the disk.
          begin
            xml_string = ""
            status = Timeout::timeout(240) {
              # We don't know when the file is going to show up, so
              # wait for it...
              until File.exists? report_path do
              sleep 1
              end

            # Read and clean up the file when it exists...
            until xml_string.include? "</MetasploitV4>" do
              sleep 5
              xml_string = File.read(report_path)
            end

            File.delete(report_path)
            }
          rescue Timeout::Error
            xml_string = "<MetasploitV4></MetasploitV4>"
          end

          xml_string
        end


        private

        # Private: connect to the database given the supplied / default options
        #
        # Returns nothing
        def _connect_database
          _send_command("db_connect #{@options[:db_user]}:#{@options[:db_pass]}@#{@options[:db_host]}/#{@options[:db_name]}")
        end

        # Private: provision a console and send the supplied command, capturing output
        #
        # Returns a valid string
        def _send_command(command)
          # Create the console and get its id
          console = @client.call("console.create")

          # Do an initial read / discard to pull out any info on the console
          # then write the command to the console
          @client.call("console.read", console["id"])
          @client.call("console.write", console["id"], "#{command}\n")

          # Initial read
          output_string = ""
          output = @client.call("console.read", console["id"])
          output_string += "#{output['data']}"

          # Very very hacky. -- There should be a way to check
          # status of a call to make sure that it isn't in an error
          # state. For now, check the output for known error heuristics
          return output_string if output_string =~ /(\[-\]|Error)/

            # Read until finished
            while (!output.has_key?("result")) do
              return unless output["busy"]
              output_string += "#{output['data']}"
              output = @client.call("console.read", console["id"])
              return "Error" if output["result"] == "failure"
              # A little bit of sleeping will prevent this infinite loop from
              # hogging up large portions of CPU time. It also adds load to the
              # msfrpc daemon as it will need to process these requests as wel..
              sleep 0.1
            end

          # Clean up console
          @client.call("console.destroy", console["id"])

          output_string
        end
      end
    end
  end
end
