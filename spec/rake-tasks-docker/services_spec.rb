
describe RakeTasksDocker::Services do
  describe 'status_from_states' do
    it 'should return failed status if a service failed' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'exited (non-zero exit code)',
      }

      expect(services.status_from_states(states)).to eq('failed')
    end

    it 'should return failed status if a service is unhealthy' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'running (unhealthy)',
      }

      expect(services.status_from_states(states)).to eq('failed')
    end

    it 'should return starting status if a service is waiting for health check to complete' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'running (starting)',
      }

      expect(services.status_from_states(states)).to eq('starting')
    end

    it 'should return started status if a service is running' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'running',
      }

      expect(services.status_from_states(states)).to eq('started')
    end

    it 'should return failed if a service is failed and others are running' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'running',
        'service2' => 'dead',
        'service3' => 'running (starting)'
      }

      expect(services.status_from_states(states)).to eq('failed')
    end

    it 'should return starting if a service is starting and others are running/succeeded' do
      services = RakeTasksDocker::Services.new()

      states = {
        'service1' => 'running',
        'service2' => 'running (starting)',
        'service3' => 'exited',
      }

      expect(services.status_from_states(states)).to eq('starting')
    end
  end
end
