require 'spec_helper'

describe Sidekiq::Status::ClientMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }

  before do
    allow(SecureRandom).to receive(:hex).once.and_return(job_id)
  end

  describe "without :expiration parameter" do

    it "sets queued status" do
      expect(StubJob.perform_async arg1: 'val1').to eq(job_id)
      expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('queued')
      expect(Sidekiq::Status::queued?(job_id)).to be_truthy
    end

    it "sets status hash ttl" do
      expect(StubJob.perform_async arg1: 'val1').to eq(job_id)
      expect(1..Sidekiq::Status::DEFAULT_EXPIRY).to cover redis.ttl("sidekiq:status:#{job_id}")
    end

    context "when redis_pool passed" do
      it "uses redis_pool" do
        redis_pool = double(:redis_pool)
        allow(redis_pool).to receive(:with)
        expect(Sidekiq).to_not receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued, redis_pool) do end
      end
    end

    context "when redis_pool is not passed" do
      it "uses Sidekiq.redis" do
        allow(Sidekiq).to receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued) do end
      end
    end

    context "when worker_class.record_initial_status? is true" do
      it 'still records the initial metadata' do
        jid = VerboseJob.perform_async(:foo => 'bar')
        expect(Sidekiq::Status.queued?(jid)).to be_truthy
        expect(Sidekiq::Status.get_all(jid)).not_to be_empty
      end
    end

    context "when worker_class.record_initial_status? is false" do
      it 'does not record the initial metadata' do
        jid = QuietJob.perform_async(:foo => 'bar')
        expect(Sidekiq::Status.queued?(jid)).to be_falsey
        expect(Sidekiq::Status.get_all(jid)).to be_empty
      end
    end
  end

  describe "with :expiration parameter" do

    let(:huge_expiration) { Sidekiq::Status::DEFAULT_EXPIRY * 100 }

    # Ensure client middleware is loaded with an expiration parameter set
    before do
      client_middleware expiration: huge_expiration
    end

    it "overwrites default expiry value" do
      StubJob.perform_async arg1: 'val1'
      expect((Sidekiq::Status::DEFAULT_EXPIRY+1)..huge_expiration).to cover redis.ttl("sidekiq:status:#{job_id}")
    end

  end
end
