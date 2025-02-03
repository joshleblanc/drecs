#include <dragonruby.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/hash.h>
#include "../external/flecs.h"
#include "../external/flecs.c"

static drb_api_t *drb_api;

static void free_flecs_world(mrb_state *mrb, void *p)
{
  ecs_world_t *world = (ecs_world_t *)p;
  free(world);
}
static const struct mrb_data_type flecs_world_data_type = { "ecs_world_t", free_flecs_world };
static struct RClass *world_class;

static void free_flecs_entity(mrb_state *mrb, void *p)
{
  ecs_entity_t *entity = (ecs_entity_t *)p;
  free(entity);
}
static const struct mrb_data_type flecs_entity_data_type = { "ecs_entity_t", free_flecs_entity };
static struct RClass *entity_class;


static mrb_value flecs_ecs_init(mrb_state *mrb, mrb_value self) {
  ecs_world_t *p = ecs_init();
  struct RData *d = drb_api->mrb_data_object_alloc(mrb, world_class, p, &flecs_world_data_type);
  struct RBasic *world = (struct RBasic *)d;
  return mrb_obj_value(world);
} 

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *state, struct drb_api_t *api) {
  drb_api = api;
  struct RClass *FFI = drb_api->mrb_module_get(state, "FFI");
  struct RClass *module = drb_api->mrb_define_module_under(state, FFI, "Flecs");
  struct RClass *base = state->object_class;

  drb_api->mrb_define_module_function(state, module, "ecs_init", flecs_world_new, MRB_ARGS_REQ(0));

  world_class = drb_api->mrb_define_class_under(state, module, "World", base);
  entity_class = drb_api->mrb_define_class_under(state, module, "Entity", base);
  MRB_SET_INSTANCE_TT(world_class, MRB_TT_DATA);
  drb_api->mrb_define_class_method(state, world_class, "new", flecs_world_new, MRB_ARGS_REQ(0));
  drb_api->mrb_define_method(state, world_class, "entity", flecs_world_entity, MRB_ARGS_REQ(0));
}
