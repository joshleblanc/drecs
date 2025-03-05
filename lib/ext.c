// https://wiki.libsdl.org/SDL2/SDL_CreateThread
// https://wiki.libsdl.org/SDL2/SDL_WaitThread
// https://wiki.libsdl.org/SDL2/SDL_AtomicSet
// https://wiki.libsdl.org/SDL2/SDL_AtomicGet
#include <dragonruby.h>
static struct drb_api_t *drb;
static SDL_Thread *thread;
static SDL_atomic_t atomic_printing;

static int background_print(void *unused)
{
  while (drb->SDL_AtomicGet(&atomic_printing)) {
    drb->drb_log_write("Game", 2, "* INFO - Hello from the Worker class!");
    drb->SDL_Delay(1000);
  }

  return 0;
}

static mrb_value start_printing_m(mrb_state *mrb, mrb_value self)
{
  drb->drb_log_write("Game", 2, "* INFO - Starting printing invoked");
  int printing = drb->SDL_AtomicGet(&atomic_printing);

  char log_message[256] = {0};
  sprintf(log_message, "* INFO - printing: %d", printing);
  drb->drb_log_write("Game", 2, log_message);

  if (printing) return mrb_nil_value();
  thread = drb->SDL_CreateThread(background_print, "background_print", NULL);
  drb->SDL_AtomicSet(&atomic_printing, 1);

  return drb->mrb_nil_value();
}

static mrb_value printing_q_m(mrb_state *mrb, mrb_value self)
{
  int printing = drb->SDL_AtomicGet(&atomic_printing);
  return printing ? mrb_true_value() : mrb_false_value();
}

static mrb_value stop_printing_m(mrb_state *mrb, mrb_value self)
{
  drb->drb_log_write("Game", 2, "* INFO - Stopping printing invoked");
  drb->SDL_AtomicSet(&atomic_printing, 0);
  drb->SDL_WaitThread(thread, NULL);
  return drb->mrb_nil_value();
}

static SDL_Thread *worker_threads[4];
static SDL_atomic_t workers_done[4];
static mrb_value worker_blocks[4];
static mrb_value worker_entities[4];

typedef struct {
  int index;
} ThreadData;

static int execute_worker(void *data)
{
  return 1;
}

static mrb_value worker_run_m(mrb_state *mrb, mrb_value self)
{
  drb->SDL_CreateThread(execute_worker, "test", NULL);
  
  return mrb_true_value();
}

// Check if all workers in a batch are done
static mrb_value workers_all_done_m(mrb_state *mrb, mrb_value self)
{
  return mrb_true_value();
}

static mrb_value wait_for_workers_m(mrb_state *mrb, mrb_value self)
{
  return drb->mrb_nil_value();
}

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *drb_local) {
  drb = drb_local;

  
  for (int i = 0; i < 4; i++) {
    drb->SDL_AtomicSet(&workers_done[i], 1);
  }

  struct RClass *worker_class = drb->mrb_define_class(mrb, "Worker", mrb->object_class);
  
  drb->mrb_define_class_method(mrb, worker_class, "run", worker_run_m, MRB_ARGS_REQ(1) | MRB_ARGS_BLOCK());
  drb->mrb_define_class_method(mrb, worker_class, "all_done?", workers_all_done_m, MRB_ARGS_NONE());
  drb->mrb_define_class_method(mrb, worker_class, "wait_all", wait_for_workers_m, MRB_ARGS_NONE());
}