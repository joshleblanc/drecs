#include <dragonruby.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/hash.h>
#include "../external/flecs.h"
#include "../external/flecs.c"

#undef mrb_float
#undef Data_Wrap_Struct
#undef Data_Make_Struct
#undef Data_Get_Struct

// This throws a redefined error
// struct RFloat {
//   MRB_OBJECT_HEADER;
//   mrb_float f;
// };

union drb_value_ {
  void *p;
#ifdef MRB_64BIT
  /* use struct to avoid bit shift. */
  struct {
    MRB_ENDIAN_LOHI(
      mrb_sym sym;
      ,uint32_t sym_flag;
    )
  };
#endif
  struct RBasic *bp;
#ifndef MRB_NO_FLOAT
  struct RFloat *fp;
#endif
  struct RInteger *ip;
  struct RCptr *vp;
  uintptr_t w;
  mrb_value value;
};

static inline union drb_value_
drb_val_union(mrb_value v)
{
  union drb_value_ x;
  x.value = v;
  return x;
}

#define mrb_float(o) drb_val_union(o).fp->f

static drb_api_t *drb_api;
static mrb_sym sym_draw_sprite;
static mrb_sym sym_ivar_path;

#define Data_Wrap_Struct(mrb,klass,type,ptr)\
  drb_api->mrb_data_object_alloc(mrb,klass,ptr,type)

#define Data_Make_Struct(mrb,klass,strct,type,sval,data_obj) do { \
  (data_obj) = Data_Wrap_Struct(mrb,klass,type,NULL);\
  (sval) = (strct *)drb_api->mrb_malloc(mrb, sizeof(strct));                     \
  { static const strct zero = { 0 }; *(sval) = zero; };\
  (data_obj)->data = (sval);\
} while (0)

#define Data_Get_Struct(mrb,obj,type,sval) do {\
  *(void**)&sval = drb_api->mrb_data_get_ptr(mrb, obj, type); \
} while (0)


// ===========================================================================
// ================ BEGIN IMPLEMENTATION
// ===========================================================================


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


static mrb_value flecs_world_new(mrb_state *mrb, mrb_value self) {
  ecs_world_t *p = ecs_init();
  struct RData *d = drb_api->mrb_data_object_alloc(mrb, world_class, p, &flecs_world_data_type);
  struct RBasic *world = (struct RBasic *)d;
  return mrb_obj_value(world);
} 

static mrb_value flecs_world_entity(mrb_state *mrb, mrb_value self) {
  ecs_world_t *world = drb_api->mrb_data_get_ptr(mrb, self, &flecs_world_data_type);
  ecs_entity_t *p = ecs_new(world);
  struct Rdata *d = drb_api->mrb_data_object_alloc(mrb, entity_class, p, &flecs_entity_data_type);
  struct RBasic *entity = (struct RBasic *)d;
  return mrb_obj_value(entity);
}

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *state, struct drb_api_t *api) {
  drb_api = api;
  struct RClass *FFI = drb_api->mrb_module_get(state, "FFI");
  struct RClass *module = drb_api->mrb_define_module_under(state, FFI, "Flecs");
  struct RClass *base = state->object_class;

  world_class = drb_api->mrb_define_class_under(state, module, "World", base);
  entity_class = drb_api->mrb_define_class_under(state, module, "Entity", base);
  MRB_SET_INSTANCE_TT(world_class, MRB_TT_DATA);
  drb_api->mrb_define_class_method(state, world_class, "new", flecs_world_new, MRB_ARGS_REQ(0));
  drb_api->mrb_define_method(state, world_class, "entity", flecs_world_entity, MRB_ARGS_REQ(0));
}
