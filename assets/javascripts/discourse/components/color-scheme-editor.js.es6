
export default Ember.Component.extend({
  actions:{
    revert(color) {
      color.revert();
    },

    undo(color) {
      color.undo();
    },
  }
});