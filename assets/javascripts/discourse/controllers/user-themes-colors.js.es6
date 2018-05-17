import { default as computed } from 'ember-addons/ember-computed-decorators';
import { url } from 'discourse/lib/computed';

export default Ember.Controller.extend({
  previewUrl: url('model.theme_id', '/user_themes/%@/preview'),

  @computed('isSaving')
  saveButtonText(isSaving) {
    return isSaving ? I18n.t('saving') : I18n.t('theme_creator.save');
  },

  actions:{
    save(){
      this.set('isSaving', true);
      this.get('model').save().then(()=>{
        this.set('isSaving', false);
      });
    }
  }

});
