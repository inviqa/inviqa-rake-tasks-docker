require 'json'

module RakeTasksDocker
  class Services
    def self.from_args(args)
      self.new(args[:services] ? args[:services].split(' ') : [])
    end

    def initialize(services = [])
      @services = services
    end

    def self.task(*task_args, &block)
      Rake::Task.define_task *task_args do |task, args|
        block.call task, self.from_args(args)
      end
    end

    def refresh
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
      if states.empty?
        return 'not started'
      elsif !(states.values & ['exited (non-zero exit code)', 'running (unhealthy)', 'restarting', 'dead']).empty?
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
      Process.spawn 'docker-compose', 'up', '-d', *@services
    end

    def logs(tail_amount = 50)
      Process.spawn 'docker-compose', 'logs', '-f', '--tail=' + tail_amount.to_s, *@services
    end

    def stop
      Process.spawn 'docker-compose', 'stop', *@services
    end

    def down
      Process.spawn 'docker-compose', 'down', '--volumes', '--rmi', 'local'
    end

    protected

    def containers
      `docker-compose ps -q #{@services.join(' ')}`.split("\n")
    end
  end
end
