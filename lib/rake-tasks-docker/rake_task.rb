
require 'timeout'

require_relative 'services'

namespace :docker do
  task :status, :services do |task, args|
    services = RakeTasksDocker::Services.new(args[:services] ? args[:services].split(' ') : [])
    puts services.status
    exit(1) if services.status != 'started'
  end

  task :up, :services do |task, args|
    services = RakeTasksDocker::Services.new(args[:services] ? args[:services].split(' ') : [])
    pid = nil

    begin
      Timeout::timeout(ENV['RAKE_DOCKER_TIMEOUT'].to_i || 0) do
        Process.wait(services.up)
        if $?.exitstatus > 0
          STDERR.puts 'The project failed to start'
          exit(1)
        end

        pid = services.logs

        loop do
          services.refresh
          case services.status
          when 'failed'
            STDERR.puts 'The project failed to start'
            exit(1)
          when 'started'
            STDERR.puts 'The project completed startup'
            exit(0)
          end
          sleep 1
        end
      end
    ensure
      Process.kill('TERM', pid) unless pid.nil?
    end
  end
end
