require 'json'

module RakeTasksDocker
  class Services
    def initialize(services = [])
      @services = services
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
        if inspection['State']
          state = inspection['State']
          if state['Running'] && state['Health']
            states[inspection['Name']] = "#{state['Status']} (#{state['Health']['Status']})"
          elsif state['ExitCode'] > 0
            states[inspection['Name']] = "#{state['Status']} (non-zero exit code)"
          else
            states[inspection['Name']] = state['Status']
          end
        end
      end
      states
    end

    def status_from_states(states)
      if states.empty? || !(states.values & ['exited (non-zero exit code)', 'running (unhealthy)', 'restarting', 'dead']).empty?
        return 'failed'
      elsif !(states.values & ['created', 'running (starting)']).empty?
        return 'starting'
      else
        return 'started'
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
      Process.spawn 'docker-compose', 'up', '-d', *@services
    end

    def logs
      Process.spawn 'docker-compose', 'logs', '-f', *@services
    end

    def stop
      system 'docker-compose', 'stop', '-v', *@services
    end

    def down
      system 'docker-compose', 'down', '--volumes', *@services
    end

    def build
      system 'eval', '$(echo $(printf "%s " $(cat docker.env))) docker-compose build --pull -v', *@services
    end

    def exec(user, command)
      @services.each do |service|
        system 'docker-compose', 'exec', '--user', user, service, command
      end
    end
  end
end
