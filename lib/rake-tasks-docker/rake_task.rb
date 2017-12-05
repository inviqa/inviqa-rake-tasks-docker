
require 'slop'
require 'timeout'
require 'highline'

require_relative 'services'

namespace :docker do
  def parse_argv
    args = ARGV
    args = ARGV[2..-1] if ARGV.length > 2
    args
  end

  def parse_options(args = [])
    args = parse_argv if args.empty?
    Slop.parse args do |options|
      options.array '-s', '--services', 'The docker services to interact with, separated by comma', default: []
      yield options if block_given?
    end
  end

  def services_option_required(options)
    options.options.select { |option| option.flags.include?('-s') }.each do |option|
      option.config[:required] = true
    end
  end

  def services_option_default(options, default_container)
    options.options.select { |option| option.flags.include?('-s') }.each do |option|
      option.config[:default] = [default_container]
    end
  end

  def parse_command(args = [], default_container = '')
    parse_options(args) do |options|
      services_option_required(options) unless default_container
      services_option_default(options, default_container) if default_container
      options.string '-u', '--user', 'The user to log in to docker containers with. Defaults to root', default: 'root'
      options.string '-c', '--command', 'The command to run', required: true
    end
  end

  def parse_hostname(args = [])
    parse_options(args) do |options|
      services_option_required(options)
      options.string '-h', '--hostname', 'The hostname to set up', required: true
    end
  end

  def docker_compose_files
    docker_compose_files = %w[docker-compose.yml docker-compose.override.yml]
    docker_compose_files << "docker-compose-dev-#{RUBY_PLATFORM.sub('darwin', 'macos').match(/(macos|linux)/)[1]}.yml"
    docker_compose_files.select { |file| File.exist? file }
  end

  def services_from_args(args, build_env = {})
    RakeTasksDocker::Services.new(
      args[:services],
      { 'COMPOSE_FILE' => docker_compose_files.join(':') },
      build_env
    )
  end

  def run_process
    Timeout.timeout(ENV['RAKE_DOCKER_TIMEOUT'].to_i || 0) do
      yield
    end
  end

  task :status do
    services = services_from_args(parse_options)
    STDOUT.puts services.status
    exit(1) if services.status != 'started'
  end

  task :up do
    STDOUT.puts '==> Starting project:'
    services = services_from_args(parse_options)
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

  task :build do
    STDOUT.puts '==> Building docker images:'
    build_env = {}
    if File.exist? 'docker.env'
      File.readlines('docker.env').each do |line|
        key_value = line.match(/^([^=]+)=(.*)$/)
        next unless key_value
        build_env[key_value[1]] = key_value[2]
      end
    end
    services = services_from_args(parse_options, build_env)
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
        next unless key_value
        key = key_value[1]
        next if env[key]
        env[key] = key_value[2]
      end
    end

    asker = HighLine.new
    env.select { |_key, value| value.empty? }.each_key do |key|
      env[key] = asker.ask "#{key}: "
    end
    File.write('docker.env', env.map { |key, value| "#{key}=#{value}" }.join("\n"))

    STDOUT.puts "==> docker.env created\n\n"
  end

  task :copy_dist do |_task, args|
    Rake::Task['docker-compose.override.yml'].invoke(*args)
    Rake::Task['docker.env'].invoke(*args)
  end

  task :setup do |_task, args|
    Rake::Task['docker:copy_dist'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
  end

  task :start do |_task, args|
    Rake::Task['docker:up'].invoke(*args)
  end

  task :stop do
    STDOUT.puts '==> Stopping project:'
    run_process do
      Process.wait(services_from_args(parse_options).stop)
      if $?.exitstatus > 0
        STDERR.puts "==> The project failed to stop\n\n"
        exit(1)
      end
    end
    STDOUT.puts "==> Project stopped\n\n"
  end

  task :restart do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :destroy do |_task, args|
    Rake::Task['docker:stop'].invoke(*args)
    STDOUT.puts '==> Removing containers and volumes for project:'
    run_process do
      Process.wait(services_from_args(parse_options).down)
      if $?.exitstatus > 0
        STDERR.puts "==> The project failed to be destroyed\n\n"
        exit(1)
      end
    end
    STDOUT.puts "==> Project containers and volumes removed\n\n"
  end

  task :reset do |_task, args|
    Rake::Task['docker:destroy'].invoke(*args)
    Rake::Task['docker:build'].invoke(*args)
    Rake::Task['docker:start'].invoke(*args)
  end

  task :ip do
    options = parse_options
    services = options[:services]
    if services.size > 1
      STDOUT.puts services_from_args(options).ip.to_json
    elsif services.size == 1
      STDOUT.puts services_from_args(options).ip[services.first]
    else
      STDERR.puts "==> Please provide a service to look up the IP for\n\n"
      exit(1)
    end
  end

  task :logs do
    options = parse_options
    services_from_args(options).logs(false)
  end

  task :command do
    command_args = parse_command
    services_from_args(command_args).exec(command_args[:user], command_args[:command])
  end

  task :bash do
    args = parse_argv
    args << "--command=bash"
    command_args = parse_command(args, 'web')
    services_from_args(command_args).exec(command_args[:user], command_args[:command])
  end

  task :hostsfile do
    options = parse_hostname
    services = options[:services]
    hostname = options[:hostname]
    if services.length != 1
      STDERR.puts "==> Please specify only one service for docker:hostsfile\n\n"
      exit(1)
    end
    service = services.first
    STDOUT.puts '==> Adding hostname to hosts'
    ip = services_from_args(options).ip[service]
    unless ip
      STDERR.puts "==> Failed to find the IP address of the #{service} container\n\n"
      exit(1)
    end
    hosts_entry = "#{ip} #{hostname}"
    current_hosts = File.read('/etc/hosts')
    if current_hosts =~ /^#{Regexp.escape(hosts_entry)}$/
      STDOUT.puts "==> Hosts file entry already present\n\n"
      exit(0)
    end

    system "echo '#{hosts_entry}' | sudo tee -a /etc/hosts"
    if $?.exitstatus > 0
      STDERR.puts "==> Failed to add hostname to hosts\n\n"
      exit(1)
    end
    STDOUT.puts '==> Added hostname to hosts'
  end
end
