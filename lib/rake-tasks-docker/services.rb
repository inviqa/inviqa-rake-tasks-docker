require 'json'
require 'shellwords'

module RakeTasksDocker
  class Services
    def initialize(services = [], docker_compose_env = {}, docker_compose_build_env = {})
      @services = services
      @docker_compose_env = docker_compose_env || {}
      @docker_compose_build_env = docker_compose_build_env || {}
    end

    def refresh
      containers = `docker-compose ps -q #{@services.join(' ')}`.split("\n")
      @inspections = []
      containers.each do |container_ref|
        @inspections << JSON.parse(`docker inspect #{container_ref}`).first
      end
    end

    def states
      states = {}
      @inspections.each do |inspection|
        next unless inspection['State']
        state = inspection['State']
        states[inspection['Name']] = if state['Running'] && state['Health']
                                       "#{state['Status']} (#{state['Health']['Status']})"
                                     elsif state['ExitCode'] > 0
                                       "#{state['Status']} (non-zero exit code)"
                                     else
                                       state['Status']
                                     end
      end
      states
    end

    def status_from_states(states)
      if states.empty? || !(states.values & ['exited (non-zero exit code)', 'running (unhealthy)', 'restarting', 'dead']).empty?
        'failed'
      elsif !(states.values & ['created', 'running (starting)']).empty?
        'starting'
      else
        'started'
      end
    end

    def status
      refresh unless @inspections
      status_from_states(states)
    end

    def ip
      refresh unless @inspections
      Hash[
        @services.zip(
          @inspections.map do |inspection|
            if RUBY_PLATFORM =~ /darwin/
              '127.0.0.1'
            else
              inspection['NetworkSettings']['Networks'].flatten()[1]['IPAddress']
            end
          end
        )
      ]
    end

    def up
      Process.spawn @docker_compose_env, 'docker-compose', 'up', '-d', *@services
    end

    def logs(background = true)
      if background
        Process.spawn @docker_compose_env, 'docker-compose', 'logs', '-f', *@services
      else
        system @docker_compose_env, 'docker-compose', 'logs', '-f', *@services
      end
    end

    def stop
      Process.spawn @docker_compose_env, 'docker-compose', 'stop', *@services
    end

    def down
      Process.spawn @docker_compose_env, 'docker-compose', 'down', '--volumes', *@services
    end

    def build
      env = @docker_compose_env.merge(@docker_compose_build_env)
      Process.spawn(env, 'docker-compose', 'build', '--pull', *@services)
    end

    def exec(user, command)
      @services.each do |service|
        docker_compose_command = "docker-compose exec --user='#{Shellwords.escape(user)}' #{Shellwords.escape(service)} #{command}"
        system @docker_compose_env, 'bash', '-c', docker_compose_command
      end
    end

    def download(source, destination)
      refresh unless @inspections
      @inspections.each do |inspection|
        service_source = inspection['Id'] + ':' + source
        host_destination = File.basename(destination)
        docker_command = "docker cp #{Shellwords.escape(service_source)} #{Shellwords.escape(host_destination)}"
        Process.spawn(@docker_compose_env, docker_command)
      end
    end

    def upload(source, destination)
      refresh unless @inspections
      @inspections.each do |inspection|
        container_destination = "/tmp/#{File.basename(destination)}"
        service_destination = inspection['Id'] + ':' + container_destination
        docker_command = "docker cp #{Shellwords.escape(source)} #{Shellwords.escape(service_destination)}"
        Process.spawn(@docker_compose_env, docker_command)
      end
    end
  end
end
