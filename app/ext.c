#include <dragonruby.h>
#include <mruby.h>
#include <mruby/string.h>
#include <mruby/array.h>
#include <mruby/hash.h>
#include "../external/flecs.h"
#include "../external/flecs.c"

static drb_api_t *drb_api;

const char *to_cstring_b(mrb_state *mrb, mrb_value v) {
  if (mrb_string_p(v)) return drb_api->mrb_string_cstr(mrb, v);
  if (mrb_symbol_p(v)) {
    mrb_sym sym = drb_api->mrb_obj_to_sym(mrb, v);
    return drb_api->mrb_sym_name(mrb, sym);
  }
  drb_api->mrb_raisef(mrb, drb_api->mrb_exc_get_id(mrb, drb_api->mrb_intern_lit(mrb, "TypeError")), "expected string or symbol, got %T", v);
}


static mrb_value flecs_ecs_init(mrb_state *mrb, mrb_value self) {
  ecs_world_t *p = ecs_init();

  return drb_api->mrb_word_boxing_cptr_value(mrb, p);
} 

static mrb_value flecs_ecs_new(mrb_state *mrb, mrb_value self) {
  mrb_value w = drb_api->mrb_get_arg1(mrb);
  ecs_world_t *world = (ecs_world_t *)mrb_cptr(w);
  ecs_entity_t p = ecs_new(world);

  return drb_api->mrb_word_boxing_cptr_value(mrb, p);
} 

static mrb_value flecs_ecs_entity_init(mrb_state *mrb, mrb_value self) {
    ecs_world_t *world;
    const char *name = NULL;

    uint32_t kw_num = 2;
    const mrb_sym kw_names[] = { drb_api->mrb_intern_lit(mrb, "world"), drb_api->mrb_intern_lit(mrb, "name") };
    mrb_value kw_values[kw_num];
    const mrb_kwargs kwargs = {
      .values = kw_values,
      .num = kw_num,
      .required = kw_num,
      .table = kw_names,
      .rest = NULL
    };
    drb_api->mrb_get_args(mrb, ":", &kwargs);
    if (!mrb_undef_p(kw_values[0])) { world = (ecs_world_t *)mrb_cptr(kw_values[0]); }
    if (!mrb_undef_p(kw_values[1])) { name = mrb_symbol(kw_values[1]); }

    ecs_entity_t entity = ecs_entity_init(world, &(ecs_entity_desc_t){
        ._canary = 1,
        .name = name
    });

    return drb_api->mrb_word_boxing_int_value(mrb, entity);

}

static mrb_value flecs_ecs_set_name(mrb_state *mrb, mrb_value self) {
    mrb_value *args = 0;
    mrb_int argc = 0;

    drb_api->mrb_get_args(mrb, "*", &args, &argc);

    ecs_world_t *world = (ecs_world_t *)mrb_cptr(args[0]);
    ecs_entity_t entity = (ecs_entity_t)mrb_fixnum(args[1]);


    const char* name = to_cstring_b(mrb, args[2]);
    return mrb_fixnum_value((mrb_int)ecs_set_name(world, entity, name));
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
  drb_api->mrb_define_module_function(state, module, "ecs_entity_init", flecs_ecs_entity_init, MRB_ARGS_KEY(2, 0));
  drb_api->mrb_define_module_function(state, module, "ecs_set_name", flecs_ecs_set_name, MRB_ARGS_REQ(3));
  // world_class = drb_api->mrb_define_class_under(state, module, "World", base);
  // entity_class = drb_api->mrb_define_class_under(state, module, "Entity", base);
  // MRB_SET_INSTANCE_TT(world_class, MRB_TT_DATA);
  // drb_api->mrb_define_class_method(state, world_class, "new", flecs_world_new, MRB_ARGS_REQ(0));
  // drb_api->mrb_define_method(state, world_class, "entity", flecs_world_entity, MRB_ARGS_REQ(0));
}
