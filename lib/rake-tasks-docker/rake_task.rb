
require 'timeout'

require_relative 'services'

namespace :docker do
  RakeTasksDocker::Services.task :status, :services do |task, services|
    puts services.status
    exit(1) if services.status != 'started'
  end

  RakeTasksDocker::Services.task :up, :services do |task, services|
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

  RakeTasksDocker::Services.task :stop, :services do |task, services|
    Process.wait(services.stop)
  end

  RakeTasksDocker::Services.task :down do |task, services|
    Process.wait(services.down)
  end
end
