# frozen_string_literal: true

module Jobs
  # NOTE: The following Sidekiq-specific APIs could not be migrated and require further review:
  # - queued (was: Sidekiq::Stats.new.enqueued)
  # - last_job_performed_at (was: Sidekiq.redis)
  # - num_email_retry_jobs (was: Sidekiq::RetrySet)
  # - cancel_scheduled_job/scheduled_for (was: Sidekiq::ScheduledSet)
  #
  # These methods are now stubbed or commented. Please implement SolidQueue/ActiveJob equivalents if needed.

  # TODO: Implement an equivalent if needed
  def self.queued
    nil
  end

  def self.run_later?
    !@run_immediately
  end

  def self.run_immediately?
    !!@run_immediately
  end

  def self.run_immediately!
    @run_immediately = true
  end

  def self.run_later!
    @run_immediately = false
  end

  def self.with_immediate_jobs
    prior = @run_immediately
    run_immediately!
    yield
  ensure
    @run_immediately = prior
  end

  # TODO: Implement equivalent using SolidQueue/ActiveJob if possible
  def self.last_job_performed_at
    nil
  end

  # TODO: Implement equivalent using SolidQueue/ActiveJob if possible
  def self.num_email_retry_jobs
    nil
  end

  # ApplicationJob base for all Discourse jobs (ActiveJob/SolidQueue)
  class ApplicationJob < ActiveJob::Base
    # You can place shared logic for all jobs here (error handling, logging, etc.)
    # For now, we preserve the error_context helper and log method.

    def log(*args)
      args.each do |arg|
        Rails.logger.info "#{Time.now.to_formatted_s(:db)}: [#{self.class.name.upcase}] #{arg}"
      end
      true
    end

    def error_context(opts, code_desc = nil, extra = {})
      ctx = {}
      ctx[:opts] = opts
      ctx[:job] = self.class
      ctx[:message] = code_desc if code_desc
      ctx.merge!(extra) if extra != nil
      ctx
    end

    # Optionally, you might want to replicate run_immediately? logic for testing/dev
    # For now, leave as is; most jobs should use perform_later.
  end

  # Legacy alias for compatibility: Jobs::Base => ApplicationJob
  Base = ApplicationJob

  # Legacy wrapper for scheduled jobs (MiniScheduler) -- review for future refactor
  class Scheduled < ApplicationJob
    extend MiniScheduler::Schedule

    def self.perform_when_readonly
      @perform_when_readonly = true
    end

    def self.perform_when_readonly?
      @perform_when_readonly || false
    end

    def perform(*args)
      super if self.class.perform_when_readonly? || !Discourse.readonly_mode?
    end
  end

  # Universal enqueue helper using ActiveJob API
  def self.enqueue(job, opts = {})
    klass =
      if job.is_a?(Class)
        job
      else
        "::Jobs::#{job.to_s.camelcase}".constantize
      end

    # Unless we want to work on all sites
    unless opts.delete(:all_sites)
      opts[:current_site_id] ||= RailsMultisite::ConnectionManagement.current_db
    end

    delay = opts.delete(:delay_for)
    queue = opts.delete(:queue)

    # Only string keys are allowed in JSON. We call `.with_indifferent_access`
    # in Jobs::Base#perform, so this is invisible to developers
    opts = opts.deep_stringify_keys

    # Simulate the args being dumped/parsed through JSON
    parsed_opts = JSON.parse(JSON.dump(opts))
    if opts != parsed_opts
      Discourse.deprecate(<<~TEXT.squish, since: "2.9", drop_from: "3.0", output_in_test: true)
        #{klass.name} was enqueued with argument values which do not cleanly serialize to/from JSON.
        This means that the job will be run with slightly different values than the ones supplied to `enqueue`.
        Argument values should be strings, booleans, numbers, or nil (or arrays/hashes of those value types).
      TEXT
    end
    opts = parsed_opts

    if ::Jobs.run_later?
      job_instance = klass.set(queue: queue)
      job_instance = job_instance.set(wait: delay) if delay.present?
      job_instance.perform_later(opts)
    else
      # Run the job synchronously (mainly for test/dev)
      klass.new.perform(opts)
    end
  end

  def self.enqueue_in(secs, job_name, opts = {})
    enqueue(job_name, opts.merge!(delay_for: secs))
  end

  def self.enqueue_at(datetime, job_name, opts = {})
    secs = [datetime.to_f - Time.zone.now.to_f, 0].max
    enqueue_in(secs, job_name, opts)
  end

  # TODO: No SolidQueue/ActiveJob equivalent for cancel_scheduled_job/scheduled_for.
  # These are Sidekiq-specific and are now stubs.
  def self.cancel_scheduled_job(job_name, opts = {})
    []
  end

  def self.scheduled_for(job_name, opts = {})
    []
  end

  # HandledExceptionWrapper is not required for ActiveJob (exceptions are already handled/reported).
  # However, if jobs depend on this for compatibility, you can preserve it.
  class HandledExceptionWrapper < StandardError
    attr_accessor :wrapped
    def initialize(ex)
      super("Wrapped #{ex.class}: #{ex.message}")
      @wrapped = ex
    end
  end
end