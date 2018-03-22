ThemeCreator::Engine.routes.draw do
  get "" => "theme_creator#list"
  post "" => "theme_creator#create"
  delete ":id" => "theme_creator#destroy"
  put ":id" => "theme_creator#update"
  get ":id/preview" => "theme_creator#preview"
  get ":id/view" => "theme_creator#share_info"
  post ":id/view" => "theme_creator#share_preview"
  post ":id/colors" => "theme_creator#create_color_scheme"
  put ":id/colors/:color_scheme_id" => "theme_creator#update_color_scheme"
  delete ":id/colors/:color_scheme_id" => "theme_creator#destroy_color_scheme"
  get "enter_sandbox/:token/:theme_key" => "theme_creator#enter_sandbox"
end
