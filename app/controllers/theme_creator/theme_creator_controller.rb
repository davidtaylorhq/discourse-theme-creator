class ThemeCreator::ThemeCreatorController < ApplicationController

  before_action :ensure_logged_in, except: [:preview, :share_preview, :share_info, :enter_sandbox]

  before_action :ensure_own_theme, only: [:destroy, :update, :create_color_scheme, :update_color_scheme, :destroy_color_scheme]
  before_action :ensure_can_see_theme, only: [:share_preview, :share_info]
  skip_before_action :check_xhr, only: [:preview, :share_preview, :enter_sandbox]
  skip_before_action :redirect_to_main_hostname_if_required, only: :enter_sandbox

  # Preview is used when actively developing a theme, it uses the GET parameter ?preview_theme_key
  def preview
    @theme ||= Theme.find(params[:id])
    raise Discourse::InvalidAccess.new() if !guardian.can_hotlink_user_theme?(@theme)

    destination = '/styleguide/' if defined? DiscourseStyleguide else '/'
    redirect_to path("#{destination}?preview_theme_key=#{@theme.key}")
  end

  # Shared preview is used when sharing the theme with others. It is only accessible via POST to avoid
  # hotlinking (reduce XSS risk)
  # This will generate an anonymous user, then send them to the sandboxed domain with a magic link
  def share_preview
    @theme ||= Theme.find(params[:id])
    raise Discourse::InvalidAccess.new() if !guardian.can_see_user_theme?(@theme)

    user = AnonymousShadowCreator.get(current_user)
    if user
      email_token = user.email_tokens.create(email: user.email)
      destination = "http://#{SiteSetting.theme_creator_sandbox_hostname}/user_themes/enter_sandbox/#{email_token.token}/#{@theme.key}"

      redirect_to destination
    else
      raise Discourse::InvalidAccess.new()
    end
  end

  def enter_sandbox
    raise Discourse::InvalidAccess.new unless request.host_with_port == SiteSetting.theme_creator_sandbox_hostname

    token = params[:token]
    valid_token = !!EmailToken.valid_token_format?(token)

    if ( user = EmailToken.confirm(token) ) && user.anonymous?
      log_on_user(user)
      theme_key = params[:theme_key]

      @theme ||= Theme.find_by(key: theme_key)
      raise Discourse::InvalidAccess.new() if !guardian.can_see_user_theme?(@theme)

      destination = defined?(DiscourseStyleguide) ? '/styleguide/' : '/'
      redirect_to path(destination), flash: { user_theme_key: @theme.key }
    else
      raise Discourse::InvalidAccess.new
    end
  end

  def share_info
    @theme ||= Theme.find(params[:id])
    raise Discourse::InvalidAccess.new() if !guardian.can_see_user_theme?(@theme)
    render json: @theme, serializer: ::BasicUserThemeSerializer, root: 'theme'
  end

  def list
    @theme = Theme.where(user_id: current_user.id).order(:name).includes(:theme_fields, :remote_theme)

    # Only present color schemes that are attached to the user's themes
    @color_schemes = ColorScheme.where(theme_id: @theme.pluck(:id)).to_a
    light = ColorScheme.new(name: I18n.t("color_schemes.default"))
    @color_schemes.unshift(light)

    payload = {
      user_themes: ActiveModel::ArraySerializer.new(@theme, each_serializer: ThemeSerializer),
      extras: {
        color_schemes: ActiveModel::ArraySerializer.new(@color_schemes, each_serializer: ColorSchemeSerializer)
      }
    }

    respond_to do |format|
      format.json { render json: payload }
    end
  end

  def create
    @theme = Theme.new(name: theme_params[:name],
                       user_id: current_user.id,
                       user_selectable: false,)

    respond_to do |format|
      if @theme.save
        format.json { render json: { user_theme: @theme }, status: :created }
      else
        format.json { render json: @theme.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    @theme = Theme.find(params[:id])

    if theme_params.key?(:color_scheme_id) && !theme_params[:color_scheme_id].nil?
      color_scheme = ColorScheme.find(theme_params[:color_scheme_id])
      if color_scheme.theme_id != @theme.id
        raise Discourse::InvalidAccess.new("Color scheme must be owned by theme.")
      end
    end

    [:name, :is_shared, :color_scheme_id].each do |field|
      if theme_params.key?(field)
        @theme.send("#{field}=", theme_params[field])
      end
    end

    set_fields

    respond_to do |format|
      if @theme.save
        format.json { render json: { user_theme: @theme }, status: :created }
      else
        format.json {
          error = @theme.errors[:color_scheme] ? I18n.t("themes.bad_color_scheme") : I18n.t("themes.other_error")
          render json: { errors: [ error ] }, status: :unprocessable_entity
        }
      end
    end
  end

  def destroy
    @theme = Theme.find(params[:id])
    @theme.destroy

    respond_to do |format|
      format.json { head :no_content }
    end
  end

  def create_color_scheme
    @theme ||= Theme.find(params[:id])

    new_scheme = ColorScheme.create_from_base(name: I18n.t('theme_creator.new_color_scheme'))
    new_scheme.theme_id = @theme.id
    new_scheme.save!

    @theme.color_scheme_id = new_scheme.id
    @theme.save!

    respond_to do |format|
      format.json { head :no_content }
    end
  end

  def update_color_scheme
    @theme ||= Theme.find(params[:id])
    @color_scheme = ColorScheme.find(params[:color_scheme_id])

    # The theme ID has been validated, so just check that this color scheme
    # really does belong to the theme
    if @color_scheme.theme_id != @theme.id
      raise Discourse::InvalidAccess.new("Cannot modify that color scheme.")
    end

    color_scheme_params = params.permit(color_scheme: [:name, colors: [:name, :hex]])[:color_scheme]

    color_scheme = ColorSchemeRevisor.revise(@color_scheme, color_scheme_params)
    if color_scheme.valid?
      render json: color_scheme, root: false
    else
      render_json_error(color_scheme)
    end
  end

  def destroy_color_scheme
    @theme ||= Theme.find(params[:id])
    @color_scheme = ColorScheme.find(params[:color_scheme_id])

    # The theme ID has been validated, so just check that this color scheme
    # really does belong to the theme
    if @color_scheme.theme_id != @theme.id
      raise Discourse::InvalidAccess.new("Cannot modify that color scheme.")
    end

    if @theme.color_scheme_id == @color_scheme.id
      @theme.color_scheme_id = nil
      @theme.save!
    end

    @color_scheme.destroy

    respond_to do |format|
      format.json { head :no_content }
    end
  end

  private

    def theme_params
      @theme_params ||=
        begin
          params.require(:user_theme).permit(
            :name,
            :is_shared,
            :color_scheme_id,
            # :default,
            # :user_selectable,
            theme_fields: [:name, :target, :value, :upload_id, :type_id],
            # child_theme_ids: []
          )
        end
    end

    def set_fields
      return unless fields = theme_params[:theme_fields]

      fields.each do |field|
        if ['common', 'mobile', 'desktop'].include?(field[:target]) && field[:name] == 'scss'
          @theme.set_field(
            target: field[:target],
            name: field[:name],
            value: field[:value],
            # type_id: field[:type_id],
            # upload_id: field[:upload_id]
          )
        end
      end
    end

    def ensure_can_see_theme
      @theme = Theme.find(params[:id])

      if !guardian.can_see_user_theme?(@theme)

        raise Discourse::InvalidAccess.new("Theme not available.")
      end
    end

    def ensure_own_theme
      @theme = Theme.find(params[:id])
      if @theme.user_id != current_user.id
        raise Discourse::InvalidAccess.new("Cannot modify another user's theme.")
      end
    end

end
