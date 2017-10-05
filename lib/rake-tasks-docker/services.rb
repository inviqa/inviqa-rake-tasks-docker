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

    def up
      system 'docker-compose', 'up', '-d', *@services
    end
  end
end