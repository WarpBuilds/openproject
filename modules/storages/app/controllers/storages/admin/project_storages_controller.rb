#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2024 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

class Storages::Admin::ProjectStoragesController < Projects::SettingsController
  model_object Storages::ProjectStorage

  before_action :find_model_object, only: %i[oauth_access_grant edit update destroy destroy_info]
  menu_item :settings_project_storages

  def external_file_storages
    @project_storages = Storages::ProjectStorage.where(project: @project).includes(:storage)
    render "/storages/project_settings/external_file_storages"
  end

  def attachments
    render "/storages/project_settings/attachments"
  end

  def new
    @available_storages = available_storages
    project_folder_mode = project_folder_mode_from_params
    storage = @available_storages.find { |s| s.id.to_s == params.dig(:storages_project_storage, :storage_id) }
    @project_storage =
      ::Storages::ProjectStorages::SetAttributesService
        .new(user: current_user, model: Storages::ProjectStorage.new, contract_class: EmptyContract)
        .call(project: @project, storage:, project_folder_mode:)
        .result
    @last_project_folders = {}

    render template: "/storages/project_settings/new"
  end

  def create
    service_result = ::Storages::ProjectStorages::CreateService
                       .new(user: current_user)
                       .call(permitted_storage_settings_params)
    @project_storage = service_result.result

    if service_result.success?
      flash[:notice] = I18n.t(:notice_successful_create)
      redirect_to_project_storages_path_with_oauth_access_grant_confirmation
    else
      @available_storages = available_storages
      render "/storages/project_settings/new"
    end
  end

  def oauth_access_grant # rubocop:disable Metrics/AbcSize
    @project_storage = @object
    storage = @project_storage.storage
    auth_state = ::Storages::Peripherals::StorageInteraction::Authentication
                   .authorization_state(storage:, user: current_user)

    if auth_state == :connected
      redirect_to(external_file_storages_project_settings_project_storages_path)
    else
      nonce = SecureRandom.uuid
      cookies["oauth_state_#{nonce}"] = {
        value: { href: external_file_storages_project_settings_project_storages_url(project_id: @project_storage.project_id),
                 storageId: @project_storage.storage_id }.to_json,
        expires: 1.hour
      }
      session[:oauth_callback_flash_modal] = oauth_access_grant_nudge_modal(authorized: true)
      redirect_to(storage.oauth_configuration.authorization_uri(state: nonce))
    end
  end

  def edit
    @project_storage = @object
    @project_storage.project_folder_mode = project_folder_mode_from_params if project_folder_mode_from_params.present?

    @last_project_folders = Storages::LastProjectFolder
                              .where(project_storage: @project_storage)
                              .pluck(:mode, :origin_folder_id)
                              .to_h

    render "/storages/project_settings/edit"
  end

  def update
    service_result = ::Storages::ProjectStorages::UpdateService
                       .new(user: current_user, model: @object)
                       .call(permitted_storage_settings_params)

    if service_result.success?
      @project_storage = service_result.result
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to_project_storages_path_with_oauth_access_grant_confirmation
    else
      @project_storage = @object
      render "/storages/project_settings/edit"
    end
  end

  def destroy
    Storages::ProjectStorages::DeleteService
      .new(user: current_user, model: @object)
      .call
      .on_failure { |service_result| flash[:error] = service_result.errors.full_messages }

    redirect_to external_file_storages_project_settings_project_storages_path
  end

  def destroy_info
    @project_storage_to_destroy = @object

    render "/storages/project_settings/destroy_info"
  end

  private

  def permitted_storage_settings_params
    params
      .require(:storages_project_storage)
      .permit("storage_id", "project_folder_mode", "project_folder_id")
      .to_h
      .reverse_merge(project_id: @project.id)
  end

  def project_folder_mode_from_params
    Storages::ProjectStorage.project_folder_modes.values.find do |mode|
      mode == params.dig(:storages_project_storage, :project_folder_mode)
    end
  end

  def available_storages
    Storages::Storage
      .visible
      .not_enabled_for_project(@project)
      .select(&:configured?)
  end

  def redirect_to_project_storages_path_with_oauth_access_grant_confirmation
    if storage_oauth_access_granted?
      redirect_to external_file_storages_project_settings_project_storages_path
    else
      redirect_to_project_storages_path_with_nudge_modal
    end
  end

  def storage_oauth_access_granted?
    OAuthClientToken
      .exists?(user: current_user, oauth_client: @project_storage.storage.oauth_client)
  end

  def redirect_to_project_storages_path_with_nudge_modal
    redirect_to(
      external_file_storages_project_settings_project_storages_path,
      flash: { modal: oauth_access_grant_nudge_modal }
    )
  end

  def oauth_access_grant_nudge_modal(authorized: false)
    {
      type: "Storages::Admin::OAuthAccessGrantNudgeModalComponent",
      parameters: {
        project_storage: @project_storage.id,
        authorized:
      }
    }
  end
end
