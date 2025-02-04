#include <dragonruby.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/hash.h>
#include "../external/flecs.h"
#include "../external/flecs.c"

static drb_api_t *drb_api;


static mrb_value flecs_ecs_init(mrb_state *mrb, mrb_value self) {
  ecs_world_t *p = ecs_init();

  return drb_api->mrb_word_boxing_cptr_value(mrb, p);
} 

static mrb_value flecs_ecs_new(mrb_state *mrb, mrb_value self) {
  mrb_value w = drb_api->mrb_get_arg1(mrb);
  ecs_world_t *world = (ecs_world_t *)mrb_cptr(w);
  ecs_entity_t *p = ecs_new(world);

  return drb_api->mrb_word_boxing_cptr_value(mrb, p);
} 

static mrb_value flecs_ecs_get_scope(mrb_state *mrb, mrb_value self) {
    mrb_value w = drb_api->mrb_get_arg1(mrb);
    ecs_world_t *world = (ecs_world_t *)mrb_cptr(w);
    return drb_api->mrb_word_boxing_cptr_value(mrb, ecs_get_scope(world));
}

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *state, struct drb_api_t *api) {
  drb_api = api;
  struct RClass *FFI = drb_api->mrb_module_get(state, "FFI");
  struct RClass *module = drb_api->mrb_define_module_under(state, FFI, "Flecs");
  struct RClass *base = state->object_class;

  drb_api->mrb_define_module_function(state, module, "ecs_init", flecs_ecs_init, MRB_ARGS_REQ(0));
  drb_api->mrb_define_module_function(state, module, "ecs_new", flecs_ecs_new, MRB_ARGS_REQ(1));
  drb_api->mrb_define_module_function(state, module, "ecs_get_scope", flecs_ecs_get_scope, MRB_ARGS_REQ(1));
  
  // drb_api->mrb_define_module_function(state, module, "ecs_set_name", flecs_entity_new, MRB_ARGS_REQ(0));

  // world_class = drb_api->mrb_define_class_under(state, module, "World", base);
  // entity_class = drb_api->mrb_define_class_under(state, module, "Entity", base);
  // MRB_SET_INSTANCE_TT(world_class, MRB_TT_DATA);
  // drb_api->mrb_define_class_method(state, world_class, "new", flecs_world_new, MRB_ARGS_REQ(0));
  // drb_api->mrb_define_method(state, world_class, "entity", flecs_world_entity, MRB_ARGS_REQ(0));
}
