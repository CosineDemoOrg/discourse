# frozen_string_literal: true

module Jobs
  class AboutStats < ::Jobs::Scheduled
    every 30.minutes

    def perform(args)
      About.refresh_stats
    end
  end
end
