
require 'timeout'
require 'highline'

require_relative 'services'

namespace :docker do
  def services_from_args(args)
    RakeTasksDocker::Services.new(args[:services] ? args[:services].split(' ') : [])
  end

  task :status, :services do |task, args|
    services = services_from_args(args)
    puts services.status
    exit(1) if services.status != 'started'
  end

  task :up, :services do |task, args|
    services = services_from_args(args)
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

  task :build, :services do |task, args|
    services = services_from_args(args)
    services.build
  end

  task :copy_dist do |task, args|
    if File.exist?('docker-compose.override.yml.dist') && !File.exist?('docker-compose.override.yml')
      FileUtils.copy('docker-compose.override.yml.dist', 'docker-compose.override.yml')
    end
    if File.exist?('docker.env.dist') && !File.exist?('docker.env')
      FileUtils.copy('docker.env.dist', 'docker.env')
    end
  end

  task :write_env do |task, args|
    asker = HighLine.new
    env = {}
    File.readlines('docker.env').each do |line|
      key_value = line.match(/^([^=]+)=(.*)$/)
      key = key_value[1]
      value = key_value[2]
      value = asker.ask "#{key}: " if value.empty?
      env[key] = value
    end
    File.write('docker.env', env.map { |key, value| "#{key}=#{value}" }.join("\n"))
  end

  task :setup, :services do |task, args|
    Rake::Task['docker:copy_dist'].invoke(*args)
    Rake::Task['docker:write_env'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
  end

  task :start, :services do |task, args|
    services_from_args(args).up
  end

  task :stop, :services do |task, args|
    services_from_args(args).stop
  end

  task :restart, :services do |task, args|
    Rake::Task['docker:stop'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :destroy, :services do |task, args|
    Rake::Task['docker:stop'].invoke(*args)
    services_from_args(args).down
  end

  task :reset, :services do |task, args|
    Rake::Task['docker:destroy'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :ip, :services do |task, args|
    puts services_from_args(args).ip
  end

  task :command, :services, :user, :cmd do |task, args|
    services_from_args(args).exec(args[:user], args[:cmd])
  end
end
