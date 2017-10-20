
require 'timeout'
require 'highline'

require_relative 'services'

namespace :docker do
  def docker_compose_files
    docker_compose_files = %w[docker-compose.yml docker-compose.override.yml]
    docker_compose_files << "docker-compose-dev-#{RUBY_PLATFORM.sub('darwin', 'macos').match(/(macos|linux)/)[1]}.yml"
    docker_compose_files.select { |file| File.exist? file }
  end

  def services_from_args(args, build_env = {})
    RakeTasksDocker::Services.new(
      args[:services] ? args[:services].split(' ') : [],
      args[:docker_compose_options] ? args[:docker_compose_options].split(' ') : [],
      { 'COMPOSE_FILE' => docker_compose_files.join(':') },
      build_env
    )
  end

  task :status, :docker_compose_options, :services do |_task, args|
    services = services_from_args(args)
    puts services.status
    exit(1) if services.status != 'started'
  end

  task :up, :docker_compose_options, :services do |_task, args|
    puts '==> Starting project:'
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

  task :build, :docker_compose_options, :services do |_task, args|
    puts '==> Building docker images:'
    build_env = {}
    if File.exist? 'docker.env'
      File.readlines('docker.env').each do |line|
        key_value = line.match(/^([^=]+)=(.*)$/)
        build_env[key_value[1]] = key_value[2]
      end
    end
    services = services_from_args(args, build_env)
    services.build
    puts "==> Docker images built\n\n"
  end

  file 'docker-compose.override.yml' => ['docker-compose.override.yml.dist'] do
    puts '==> Creating docker-compose.override.yml if it doesn\'t exist:'
    asker = HighLine.new
    if !File.exist?('docker-compose.override.yml') || asker.agree('Dist file has changed, okay to overwrite docker-compose.override.yml? (y/n): ')
      cp('docker-compose.override.yml.dist', 'docker-compose.override.yml')
      puts "==> docker-compose.override.yml created\n\n"
    else
      puts "==> docker-compose.override.yml skipped\n\n"
    end
  end

  file 'docker.env' => ['docker.env.dist'] do
    puts '==> Creating docker.env if it doesn\'t exist:'
    env = {}

    %w[docker.env docker.env.dist].each do |file|
      next unless File.exist?(file)
      File.readlines(file).each do |line|
        key_value = line.match(/^([^=]+)=(.*)$/)
        key = key_value[1]
        next if env[key]
        env[key] = key_value[2]
      end
    end

    asker = HighLine.new
    env.select { |_key, value| value.empty? }.each do |key, _value|
      env[key] = asker.ask "#{key}: "
    end
    File.write('docker.env', env.map { |key, value| "#{key}=#{value}" }.join("\n\n"))

    puts "==> docker.env created\n\n"
  end

  task :copy_dist do |_task, args|
    Rake::Task['docker-compose.override.yml'].invoke(*args)
    Rake::Task['docker.env'].invoke(*args)
  end

  task :setup, :docker_compose_options, :services do |_task, args|
    Rake::Task['docker:copy_dist'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
  end

  task :start, :docker_compose_options, :services do |_task, args|
    Rake::Task['docker:up'].invoke(*args)
  end

  task :stop, :docker_compose_options, :services do |_task, args|
    puts '==> Stopping project:'
    services_from_args(args).stop
    puts "==> Project stopped\n\n"
  end

  task :restart, :docker_compose_options, :services do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :destroy, :docker_compose_options, :services do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    puts '==> Removing containers and volumes for project:'
    services_from_args(args).down
    puts "==> Project containers and volumes removed\n\n"
  end

  task :reset, :docker_compose_options, :services do |_task, args|
    Rake::Task['docker:destroy'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :ip, :docker_compose_options, :services do |_task, args|
    puts services_from_args(args).ip
  end

  task :command, :docker_compose_options, :services, :user, :cmd do |_task, args|
    services_from_args(args).exec(args[:user], args[:cmd])
  end
end
