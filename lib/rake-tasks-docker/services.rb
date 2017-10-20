require 'json'

module RakeTasksDocker
  class Services
    def initialize(services = [], docker_compose_options = [], docker_compose_env = {}, docker_compose_build_env = {})
      @services = services
      @docker_compose_options = docker_compose_options
      @docker_compose_env = docker_compose_env || {}
      @docker_compose_build_env = docker_compose_build_env || {}
    end

    def refresh
      containers = `docker-compose #{@docker_compose_options.join(' ')} ps -q #{@services.join(' ')}`.split("\n")
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
      Hash[@services.zip(@inspections.map { |inspection| inspection[:NetworkSettings][:Networks][:IPAddress] })]
    end

    def up
      Process.spawn @docker_compose_env, 'docker-compose', *@docker_compose_options, 'up', '-d', *@services
    end

    def logs
      Process.spawn @docker_compose_env, 'docker-compose', *@docker_compose_options, 'logs', '-f', *@services
    end

    def stop
      Process.spawn @docker_compose_env, 'docker-compose', *@docker_compose_options, 'stop', *@services
    end

    def down
      Process.spawn @docker_compose_env, 'docker-compose', *@docker_compose_options, 'down', '--volumes', *@services
    end

    def build
      env = @docker_compose_env.merge(@docker_compose_build_env)
      Process.spawn(env, 'docker-compose', *@docker_compose_options, 'build', '--pull', *@services)
    end

    def exec(user, command)
      @services.each do |service|
        Process.spawn @docker_compose_env, 'docker-compose', *@docker_compose_options, 'exec', '--user', user, service, command
      end
    end
  end
end
