#include <dragonruby.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/hash.h>

#define FNV_PRIME 16777619
#define FNV_OFFSET_BASIS 2166136261

static drb_api_t *drb_api;

static struct RClass *system_class;
static struct RClass *entity_class;
static void free_system(mrb_state *mrb, void *p) {
  void *system = p;
  free(system);
}
static void free_void(mrb_state *mrb, void *p) {
  free(p);
}
static void free_entity(mrb_state *mrb, void *p) {
  void *entity = p;
  free(entity);
}

static const struct mrb_data_type void_data_type = { "void", free_void };
static const struct mrb_data_type system_data_type = { "system", free_system };
static const struct mrb_data_type entity_data_type = { "entity", free_entity };


const char *to_cstring_b(mrb_state *mrb, mrb_value v) {
  if (mrb_string_p(v)) return drb_api->mrb_string_cstr(mrb, v);
  if (mrb_symbol_p(v)) return drb_api->mrb_sym_name(mrb, mrb_symbol(v));
  drb_api->mrb_raisef(mrb, drb_api->mrb_exc_get_id(mrb, drb_api->mrb_intern_lit(mrb, "TypeError")), "expected string or symbol, got %T", v);
}

static mrb_value system_new(mrb_state *mrb, mrb_value self) {
  mrb_value *args = 0;
  mrb_int argc = 0;
  drb_api->mrb_get_args(mrb, "*", &args, &argc);

  struct RData *data = drb_api->mrb_data_object_alloc(mrb, system_class, NULL, &void_data_type);

  struct RBasic *basic = (struct RBasic *)data;

  mrb_sym iv_name = drb_api->mrb_intern_lit(mrb, "@name");
  mrb_sym iv_disabled = drb_api->mrb_intern_lit(mrb, "@disabled");


  if(argc > 0) {
    const char *name = to_cstring_b(mrb, args[0]);
    drb_api->mrb_iv_set(mrb, drb_api->mrb_obj_value(basic), iv_name, drb_api->mrb_str_new_cstr(mrb, name));
  }
  drb_api->mrb_iv_set(mrb, drb_api->mrb_obj_value(basic), iv_disabled, mrb_false_value());

  return drb_api->mrb_obj_value(basic);
}

static mrb_value define_prop(mrb_state *mrb, mrb_value self, const char *label) {
  mrb_value *args = 0;
  mrb_int argc = 0;
  mrb_value blk;

  drb_api->mrb_get_args(mrb, "*&", &args, &argc, &blk);


  mrb_sym iv_name = drb_api->mrb_intern_cstr(mrb, label);
  mrb_value name = drb_api->mrb_iv_get(mrb, self, iv_name);

  if(!mrb_nil_p(blk)) {
    drb_api->mrb_iv_set(mrb, self, iv_name, blk);
  } else if(argc > 0) {
    mrb_value value = drb_api->mrb_get_arg1(mrb);
    drb_api->mrb_iv_set(mrb, self, iv_name, value);
  } else {
    return drb_api->mrb_iv_get(mrb, self, iv_name);
  }

  return drb_api->mrb_nil_value();
}

static mrb_value system_name(mrb_state *mrb, mrb_value self) {
  return define_prop(mrb, self, "@name");
}

static mrb_value system_callback(mrb_state *mrb, mrb_value self) {
  return define_prop(mrb, self, "@callback");
}

static mrb_value system_query(mrb_state *mrb, mrb_value self) {
  return define_prop(mrb, self, "@query");
}

static mrb_value system_disabled(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_disabled = drb_api->mrb_intern_lit(mrb, "@disabled");
  return drb_api->mrb_iv_get(mrb, self, iv_disabled);
}

static mrb_value system_enable(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_disabled = drb_api->mrb_intern_lit(mrb, "@disabled");
  mrb_value value = mrb_false_value();
  drb_api->mrb_iv_set(mrb, self, iv_disabled, value);
  return value;
}

static mrb_value system_disable(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_disabled = drb_api->mrb_intern_lit(mrb, "@disabled");
  mrb_value value = mrb_true_value();
  drb_api->mrb_iv_set(mrb, self, iv_disabled, value);
  return value;
}

static mrb_value system_set_world(mrb_state *mrb, mrb_value self) {
  mrb_value *args = 0;
  mrb_int argc = 0;
  drb_api->mrb_get_args(mrb, "*", &args, &argc);
  drb_api->mrb_iv_set(mrb, self, drb_api->mrb_intern_lit(mrb, "@world"), args[0]);
  return args[0];
}

static mrb_value system_get_world(mrb_state *mrb, mrb_value self) {
  return drb_api->mrb_iv_get(mrb, self, drb_api->mrb_intern_lit(mrb, "@world"));
}

static mrb_value entity_new(mrb_state *mrb, mrb_value self) {
  struct RData *data = drb_api->mrb_data_object_alloc(mrb, entity_class, NULL, &entity_data_type);
  struct RBasic *basic = (struct RBasic *)data;

  // Initialize instance variables
  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  mrb_sym iv_relationships = drb_api->mrb_intern_lit(mrb, "@relationships");
  mrb_sym iv_archetypes = drb_api->mrb_intern_lit(mrb, "@archetypes");

  drb_api->mrb_iv_set(mrb, drb_api->mrb_obj_value(basic), iv_components, drb_api->mrb_hash_new(mrb));
  drb_api->mrb_iv_set(mrb, drb_api->mrb_obj_value(basic), iv_relationships, drb_api->mrb_ary_new(mrb));
  drb_api->mrb_iv_set(mrb, drb_api->mrb_obj_value(basic), iv_archetypes, drb_api->mrb_ary_new(mrb));

  return drb_api->mrb_obj_value(basic);
}

static mrb_value entity_name(mrb_state *mrb, mrb_value self) {
  return define_prop(mrb, self, "@name");
}

static mrb_value entity_as(mrb_state *mrb, mrb_value self) {
  return define_prop(mrb, self, "@as");
}

static mrb_value entity_relationship(mrb_state *mrb, mrb_value self) {
  mrb_value key, entity;
  drb_api->mrb_get_args(mrb, "oo", &key, &entity);

  mrb_value hash = drb_api->mrb_hash_new(mrb);
  drb_api->mrb_hash_set(mrb, hash, key, entity);

  mrb_sym iv_relationships = drb_api->mrb_intern_lit(mrb, "@relationships");
  mrb_value relationships = drb_api->mrb_iv_get(mrb, self, iv_relationships);
  drb_api->mrb_ary_push(mrb, relationships, hash);

  return drb_api->mrb_nil_value();
}

static mrb_value entity_get_component(mrb_state *mrb, mrb_value self) {
  mrb_value key;
  drb_api->mrb_get_args(mrb, "o", &key);

  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  mrb_value components = drb_api->mrb_iv_get(mrb, self, iv_components);
  return drb_api->mrb_hash_get(mrb, components, key);
}

static mrb_value entity_component(mrb_state *mrb, mrb_value self) {
  mrb_value key, data = mrb_nil_value();

  drb_api->mrb_get_args(mrb, "o|o", &key, &data);
  const char* key_str = to_cstring_b(mrb, key);

  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  mrb_value components = drb_api->mrb_iv_get(mrb, self, iv_components);
  drb_api->mrb_hash_set(mrb, components, key, data);

  drb_api->mrb_define_singleton_method(mrb, mrb_obj_ptr(self), key_str, entity_get_component, MRB_ARGS_REQ(1));

  return drb_api->mrb_nil_value();
}

static mrb_value entity_has_components(mrb_state *mrb, mrb_value self) {
  mrb_value *components;
  mrb_int argc;
  drb_api->mrb_get_args(mrb, "*", &components, &argc);

  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  mrb_value entity_components = drb_api->mrb_iv_get(mrb, self, iv_components);
  mrb_value keys = drb_api->mrb_hash_keys(mrb, entity_components);
  struct RArray *ary = (struct RArray *)&keys;

  for (int i = 0; i < argc; i++) {
    mrb_bool found = FALSE;
    for (int j = 0; j < RARRAY_LEN(keys); j++) {
      if (drb_api->mrb_obj_eq(mrb, components[i], drb_api->mrb_ary_entry(keys, j))) {
        found = TRUE;
        break;
      }
    }
    if (!found) return mrb_false_value();
  }
  return mrb_true_value();
}

static mrb_int hash_str_array(mrb_state *mrb, mrb_value arr) {
  mrb_int hash = FNV_OFFSET_BASIS;
  mrb_int len = RARRAY_LEN(arr);
  
  for (int i = 0; i < len; i++) {
    mrb_value str = drb_api->mrb_obj_as_string(mrb, drb_api->mrb_ary_entry(arr, i));
    const char *ptr = drb_api->mrb_string_cstr(mrb, str);
    while (*ptr) {
      hash ^= (unsigned char)*ptr++;
      hash *= FNV_PRIME;
    }
    // Add a separator to avoid collisions between ["a","bc"] and ["ab","c"]
    hash ^= ',';
    hash *= FNV_PRIME;
  }
  
  return hash;
}

static mrb_value entity_generate_archetypes(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  mrb_sym iv_archetypes = drb_api->mrb_intern_lit(mrb, "@archetypes");

  mrb_value components = drb_api->mrb_iv_get(mrb, self, iv_components);
  mrb_value keys = drb_api->mrb_hash_keys(mrb, components);
  mrb_value archetypes = drb_api->mrb_ary_new(mrb);

  // Sort the component keys
  mrb_int len = RARRAY_LEN(keys);
  for (int i = 0; i < len; i++) {
    for (int j = i + 1; j < len; j++) {
      if (drb_api->mrb_str_cmp(mrb, 
          drb_api->mrb_obj_as_string(mrb, drb_api->mrb_ary_entry(keys, i)),
          drb_api->mrb_obj_as_string(mrb, drb_api->mrb_ary_entry(keys, j))) > 0) {
        mrb_value temp = drb_api->mrb_ary_entry(keys, i);
        drb_api->mrb_ary_set(mrb, keys, i, drb_api->mrb_ary_entry(keys, j));
        drb_api->mrb_ary_set(mrb, keys, j, temp);
      }
    }
  }

  // Generate archetypes for each subset of components
  for (int i = 0; i < len; i++) {
    mrb_value subset = drb_api->mrb_ary_new(mrb);
    for (int j = i; j < len; j++) {
      drb_api->mrb_ary_push(mrb, subset, drb_api->mrb_ary_entry(keys, j));
    }
    mrb_int hash = hash_str_array(mrb, subset);
    drb_api->mrb_ary_push(mrb, archetypes, drb_api->mrb_int_value(mrb, hash));
  }

  drb_api->mrb_iv_set(mrb, self, iv_archetypes, archetypes);
  return drb_api->mrb_nil_value();
}

static mrb_value entity_components(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_components = drb_api->mrb_intern_lit(mrb, "@components");
  return drb_api->mrb_iv_get(mrb, self, iv_components);
}

static mrb_value entity_archetypes(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_archetypes = drb_api->mrb_intern_lit(mrb, "@archetypes");
  return drb_api->mrb_iv_get(mrb, self, iv_archetypes);
}

static mrb_value entity_get_world(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_world = drb_api->mrb_intern_lit(mrb, "@world");
  return drb_api->mrb_iv_get(mrb, self, iv_world);
}

static mrb_value entity_set_world(mrb_state *mrb, mrb_value self) {
  mrb_value *args = 0;
  mrb_int argc = 0;
  drb_api->mrb_get_args(mrb, "*", &args, &argc);
  drb_api->mrb_iv_set(mrb, self, drb_api->mrb_intern_lit(mrb, "@world"), args[0]);
  return args[0];
}

static mrb_value entity_set_id(mrb_state *mrb, mrb_value self) {
  mrb_value *args = 0;
  mrb_int argc = 0;
  drb_api->mrb_get_args(mrb, "*", &args, &argc);
  drb_api->mrb_iv_set(mrb, self, drb_api->mrb_intern_lit(mrb, "@_id"), args[0]);
  return args[0];
}

static mrb_value entity_id(mrb_state *mrb, mrb_value self) {
  mrb_sym iv_id = drb_api->mrb_intern_lit(mrb, "@_id");
  return drb_api->mrb_iv_get(mrb, self, iv_id);
}

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *state, struct drb_api_t *api) {
  drb_api = api;
  struct RClass *FFI = drb_api->mrb_module_get(state, "FFI");
  struct RClass *module = drb_api->mrb_define_module_under(state, FFI, "Drecs");
  struct RClass *base = state->object_class;

  // drb_api->mrb_define_module_function(state, module, "ecs_init", flecs_ecs_init, MRB_ARGS_REQ(0));
  // drb_api->mrb_define_module_function(state, module, "ecs_new", flecs_ecs_new, MRB_ARGS_REQ(1));
  // drb_api->mrb_define_module_function(state, module, "ecs_get_scope", flecs_ecs_get_scope, MRB_ARGS_REQ(1));
  // drb_api->mrb_define_module_function(state, module, "ecs_entity_init", flecs_ecs_entity_init, MRB_ARGS_KEY(2, 0));

  system_class = drb_api->mrb_define_class_under(state, module, "System", base);
  MRB_SET_INSTANCE_TT(system_class, MRB_TT_DATA);
  drb_api->mrb_define_class_method(state, system_class, "new", system_new, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, system_class, "name", system_name, MRB_ARGS_OPT(1));
  drb_api->mrb_define_method(state, system_class, "callback", system_callback, MRB_ARGS_OPT(1));
  drb_api->mrb_define_method(state, system_class, "query", system_query, MRB_ARGS_OPT(1));
  drb_api->mrb_define_method(state, system_class, "disable!", system_disable, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, system_class, "enable!", system_enable, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, system_class, "disabled?", system_disabled, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, system_class, "world=", system_set_world, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, system_class, "world", system_get_world, MRB_ARGS_REQ(0));

  entity_class = drb_api->mrb_define_class(state, "Entity", api->mrb_class_get(state, "Object"));
  MRB_SET_INSTANCE_TT(entity_class, MRB_TT_DATA);

  drb_api->mrb_define_class_method(state, entity_class, "new", entity_new, MRB_ARGS_NONE());
  drb_api->mrb_define_method(state, entity_class, "name", entity_name, MRB_ARGS_OPT(1));
  drb_api->mrb_define_method(state, entity_class, "as", entity_as, MRB_ARGS_OPT(1));
  drb_api->mrb_define_method(state, entity_class, "relationship", entity_relationship, MRB_ARGS_REQ(2));
  drb_api->mrb_define_method(state, entity_class, "component", entity_component, MRB_ARGS_ARG(1, 1));
  drb_api->mrb_define_method(state, entity_class, "has_components?", entity_has_components, MRB_ARGS_ANY());
  drb_api->mrb_define_method(state, entity_class, "generate_archetypes!", entity_generate_archetypes, MRB_ARGS_NONE());
  drb_api->mrb_define_method(state, entity_class, "archetypes", entity_archetypes, MRB_ARGS_REQ(0));
  drb_api->mrb_define_method(state, entity_class, "components", entity_components, MRB_ARGS_REQ(0));
  drb_api->mrb_define_method(state, entity_class, "world", entity_get_world, MRB_ARGS_REQ(0));
  drb_api->mrb_define_method(state, entity_class, "world=", entity_set_world, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, entity_class, "_id=", entity_set_id, MRB_ARGS_REQ(1));
  drb_api->mrb_define_method(state, entity_class, "_id", entity_id, MRB_ARGS_REQ(0));

  // entity_class = drb_api->mrb_define_class_under(state, module, "Entity", base);
  // MRB_SET_INSTANCE_TT(world_class, MRB_TT_DATA);
  // drb_api->mrb_define_class_method(state, world_class, "new", flecs_world_new, MRB_ARGS_REQ(0));
  // drb_api->mrb_define_method(state, world_class, "entity", flecs_world_entity, MRB_ARGS_REQ(0));
}
