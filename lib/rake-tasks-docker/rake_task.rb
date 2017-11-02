
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
      { 'COMPOSE_FILE' => docker_compose_files.join(':') },
      build_env
    )
  end

  def run_process(&process)
    Timeout::timeout(ENV['RAKE_DOCKER_TIMEOUT'].to_i || 0) do
      yield
    end
  end

  task :status, :services do |_task, args|
    services = services_from_args(args)
    STDOUT.puts services.status
    exit(1) if services.status != 'started'
  end

  task :up, :services do |_task, args|
    STDOUT.puts '==> Starting project:'
    services = services_from_args(args)
    pid = nil

    begin
      run_process do
        Process.wait(services.up)
        if $?.exitstatus > 0
          STDERR.puts "==> The project failed to start\n\n"
          exit(1)
        end

        pid = services.logs
        loop do
          services.refresh
          case services.status
          when 'failed'
            STDERR.puts "\n\n==> The project failed to start\n\n"
            exit(1)
          when 'started'
            STDERR.puts "\n\n==> The project completed startup\n\n"
            exit(0)
          end
          sleep 1
        end
      end
    ensure
      Process.kill('TERM', pid) unless pid.nil?
    end
  end

  task :build, :services do |_task, args|
    STDOUT.puts '==> Building docker images:'
    build_env = {}
    if File.exist? 'docker.env'
      File.readlines('docker.env').each do |line|
        key_value = line.match(/^([^=]+)=(.*)$/)
        build_env[key_value[1]] = key_value[2]
      end
    end
    services = services_from_args(args, build_env)
    run_process do
      Process.wait(services.build)
      if $?.exitstatus > 0
        STDERR.puts "==> The project failed to build\n\n"
        exit(1)
      end
    end
    STDOUT.puts "==> Docker images built\n\n"
  end

  file 'docker-compose.override.yml' => ['docker-compose.override.yml.dist'] do
    STDOUT.puts '==> Creating docker-compose.override.yml if it doesn\'t exist:'
    asker = HighLine.new
    if !File.exist?('docker-compose.override.yml') || asker.agree('Dist file has changed, okay to overwrite docker-compose.override.yml? (y/n): ')
      cp('docker-compose.override.yml.dist', 'docker-compose.override.yml')
      STDOUT.puts "==> docker-compose.override.yml created\n\n"
    else
      STDOUT.puts "==> docker-compose.override.yml skipped\n\n"
    end
  end

  file 'docker.env' => ['docker.env.dist'] do
    STDOUT.puts '==> Creating docker.env if it doesn\'t exist:'
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
    env.select { |_key, value| value.empty? }.each_key do |key|
      env[key] = asker.ask "#{key}: "
    end
    File.write('docker.env', env.map { |key, value| "#{key}=#{value}" }.join("\n\n"))

    STDOUT.puts "==> docker.env created\n\n"
  end

  task :copy_dist do |_task, args|
    Rake::Task['docker-compose.override.yml'].invoke(*args)
    Rake::Task['docker.env'].invoke(*args)
  end

  task :setup, :services do |_task, args|
    Rake::Task['docker:copy_dist'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
  end

  task :start, :services do |_task, args|
    Rake::Task['docker:up'].invoke(*args)
  end

  task :stop, :services do |_task, args|
    STDOUT.puts '==> Stopping project:'
    run_process do
      Process.wait(services_from_args(args).stop)
      if $?.exitstatus > 0
        STDERR.puts "==> The project failed to stop\n\n"
        exit(1)
      end
    end
    STDOUT.puts "==> Project stopped\n\n"
  end

  task :restart, :services do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :destroy, :services do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    STDOUT.puts '==> Removing containers and volumes for project:'
    run_process do
      Process.wait(services_from_args(args).down)
      if $?.exitstatus > 0
        STDERR.puts "==> The project failed to be destroyed\n\n"
        exit(1)
      end
    end
    STDOUT.puts "==> Project containers and volumes removed\n\n"
  end

  task :reset, :services do |_task, args|
    Rake::Task['docker:destroy'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :ip, :services do |_task, args|
    STDOUT.puts services_from_args(args).ip
  end

  task :command, :services, :user, :cmd do |_task, args|
    services_from_args(args).exec(args[:user], args[:cmd])
  end
end
