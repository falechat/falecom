module Dashboard
  class UsersController < ApplicationController
    def update_availability
      previous = Current.user.availability
      Current.user.update!(availability: params.fetch(:availability))

      Events::Emit.call(
        name: "users:availability_changed",
        subject: Current.user,
        actor: Current.user,
        payload: {from: previous, to: Current.user.availability}
      )

      if Current.user.online? && previous != "online"
        enqueue_pending_assignments
      end

      respond_to do |fmt|
        fmt.turbo_stream { head :ok }
        fmt.html { redirect_back fallback_location: root_path }
      end
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_content
    end

    private

    def enqueue_pending_assignments
      channel_ids = Current.user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
      Conversation.where(channel_id: channel_ids, status: "queued", assignee_id: nil).pluck(:id).each do |cid|
        AutoAssignJob.perform_later(cid)
      end
    end
  end
end
