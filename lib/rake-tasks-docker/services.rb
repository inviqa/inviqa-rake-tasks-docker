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
      Process.spawn 'docker-compose', 'up', '-d', *@services
    end

    def logs
      Process.spawn 'docker-compose', 'logs', '-f', *@services
    end

    def stop
      system 'docker-compose', 'stop', *@services
    end

    def down
      system 'docker-compose', 'down', '--volumes', *@services
    end

    def build
      env = {}
      if File.exist? 'docker.env'
        File.readlines('docker.env').each do |line|
          key_value = line.match(/^([^=]+)=(.*)$/)
          env[key_value[1]] = key_value[2]
        end
      end
      system(env, 'docker-compose', 'build', '--pull', *@services)
    end

    def exec(user, command)
      @services.each do |service|
        system 'docker-compose', 'exec', '--user', user, service, command
      end
    end
  end
end
