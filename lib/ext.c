// https://wiki.libsdl.org/SDL2/SDL_CreateThread
// https://wiki.libsdl.org/SDL2/SDL_WaitThread
// https://wiki.libsdl.org/SDL2/SDL_AtomicSet
// https://wiki.libsdl.org/SDL2/SDL_AtomicGet
#include <dragonruby.h>
static struct drb_api_t *drb;
static SDL_Thread *worker_threads[4];
static SDL_atomic_t workers_done[4];
static mrb_value worker_blocks[4];
static mrb_value worker_entities[4];

typedef struct {
  int index;
} ThreadData;

// Worker thread function that executes a Ruby block on an entity
static int execute_worker(void *data) {
  if (data == NULL) {
    return 0;
  }

  ThreadData *thread_data = data;
  int worker_id = thread_data->index;
  mrb_state *mrb = drb->mrb_open();
  
  mrb_value block = worker_blocks[worker_id];
  mrb_value entity = worker_entities[worker_id];
  
  drb->mrb_yield(mrb, block, entity);
  
  drb->SDL_AtomicSet(&workers_done[worker_id], 1);
  
  drb->mrb_close(mrb);

  return 1;
}

static mrb_value worker_run_m(mrb_state *mrb, mrb_value self) {

  mrb_value entity;
  mrb_value block;
  
  drb->mrb_get_args(mrb, "o&", &entity, &block);
  
  int worker_id = -1;
  for (int i = 0; i < 4; i++) {
    if (drb->SDL_AtomicGet(&workers_done[i]) == 1) {
      worker_id = i;
      break;
    }
  }
  
  if (worker_id == -1) {
    return mrb_false_value();
  }
  
  worker_blocks[worker_id] = block;
  worker_entities[worker_id] = entity;
  
  drb->SDL_AtomicSet(&workers_done[worker_id], 0);
  
  char thread_name[20];
  sprintf(thread_name, "worker_%d", worker_id);

  ThreadData *data = malloc(sizeof(ThreadData));
  data->index = worker_id;

  worker_threads[worker_id] = drb->SDL_CreateThread(execute_worker, thread_name, data);
  
  return mrb_true_value();
}

static mrb_value workers_all_done_m(mrb_state *mrb, mrb_value self) {
  for (int i = 0; i < 4; i++) {
    if (drb->SDL_AtomicGet(&workers_done[i]) == 0) {
      return mrb_false_value();
    }
  }
  
  return mrb_true_value();
}

static mrb_value wait_for_workers_m(mrb_state *mrb, mrb_value self) {
  for (int i = 0; i < 4; i++) {
    if (drb->SDL_AtomicGet(&workers_done[i]) == 0) {
      drb->SDL_WaitThread(worker_threads[i], NULL);
      drb->SDL_AtomicSet(&workers_done[i], 1);
    }
  }
  
  return drb->mrb_nil_value();
}

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *drb_local) {
  drb = drb_local;

  drb->drb_log_write("Game", 2, "* INFO - Registering C extension");
  
  for (int i = 0; i < 4; i++) {
    drb->SDL_AtomicSet(&workers_done[i], 1);
  }

  drb->drb_log_write("Game", 2, "* INFO - Registering Worker class");
  struct RClass *worker_class = drb->mrb_define_class(mrb, "Worker", mrb->object_class);
  
  drb->drb_log_write("Game", 2, "* INFO - Defining run method");
  drb->mrb_define_class_method(mrb, worker_class, "run", worker_run_m, MRB_ARGS_REQ(1) | MRB_ARGS_BLOCK());
  drb->drb_log_write("Game", 2, "* INFO - Defining all_done? method");
  drb->mrb_define_class_method(mrb, worker_class, "all_done?", workers_all_done_m, MRB_ARGS_NONE());
  drb->drb_log_write("Game", 2, "* INFO - Defining wait_all method");
  drb->mrb_define_class_method(mrb, worker_class, "wait_all", wait_for_workers_m, MRB_ARGS_NONE());
}