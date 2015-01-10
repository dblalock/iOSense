
#include <pebble.h>

// ================================================================
// Constants
// ================================================================

// set these to mess with stuff
#define SAMPLE_RATE ACCEL_SAMPLING_100HZ  // *not* 100, just a flag
#define SAMPLE_BATCH 20     // must be a multiple of DOWNSAMPLE_BY
#define BUFFER_SAMPLE_RATE 20
#define SAMPLE_ELEMENTS 3
#define BUFFER_T int8_t
#define BUFFER_QUANTIZE_SHIFT 4
#define BUFFER_QUANTIZE_MASK 0xff

// derived constants
#define DOWNSAMPLE_BY (100 / BUFFER_SAMPLE_RATE)  //assumes 100Hz raw sampling
#define DOWNSAMPLE (DOWNSAMPLE_BY > 1)
#define BUFFER_LEN (BUFFER_SAMPLE_RATE * SAMPLE_ELEMENTS)
#define BUFFER_END_PADDING 3
#define BUFFER_PAD_VALUE (-128)
#define BUFFER_LEN_WITH_PADDING (BUFFER_LEN + BUFFER_END_PADDING)

static const uint32_t INBOUND_SIZE = 64;
static const uint32_t OUTBOUND_SIZE = 512;

static const uint8_t TRANSACTION_ID_KEY = 0x1;
static const uint8_t NUM_BYTES_KEY    = 0x2;
static const uint8_t DATA_KEY           = 0x3;

// ================================================================
// Static vars
// ================================================================

static Window *window;
static TextLayer *text_layer;
static char s_buffer[128];
static char time_buffer[128];
static uint32_t totalBytes = 0;
static DataLoggingSessionRef data_log;
static BUFFER_T data_buff[BUFFER_LEN_WITH_PADDING];

static int shouldShowAccelData = 0;
static int showingAccelData = 0;

static bool msg_run = false;

// ================================================================
// Utility funcs
// ================================================================

static inline BUFFER_T quantize(int16_t x) {
  if (x > (127 << BUFFER_QUANTIZE_SHIFT)) {
    return 127;
  } else if (x < (-128 << BUFFER_QUANTIZE_SHIFT)) {
    return -128;
  }
  int16_t shifted = x >> BUFFER_QUANTIZE_SHIFT;
  int16_t masked = shifted & BUFFER_QUANTIZE_MASK;
  return (BUFFER_T) masked;
}

// ================================================================
// Displaying crap
// ================================================================

static uint8_t justStarted = 1;
static void show_time() {
  if (showingAccelData || justStarted) {
    text_layer_set_font(text_layer, fonts_get_system_font(FONT_KEY_ROBOTO_BOLD_SUBSET_49));
    text_layer_set_text(text_layer, time_buffer);
    justStarted = 0;
  }
  showingAccelData = 0;
}

static void handle_tick(struct tm *tick_time, TimeUnits units_changed) {
  if (tick_time->tm_hour < 10) {
    snprintf(time_buffer, 16, "\n %2d:%02d", tick_time->tm_hour, tick_time->tm_min);
  } else {
    snprintf(time_buffer, 16, "\n%2d:%02d", tick_time->tm_hour, tick_time->tm_min);
  }
  if (! shouldShowAccelData) {
    show_time();
  }
}

static void show_accel_data(AccelRawData* data) {
  if (! showingAccelData) {
    text_layer_set_font(text_layer, fonts_get_system_font(FONT_KEY_GOTHIC_24));
  }
  showingAccelData = 1;

  snprintf(s_buffer, sizeof(s_buffer),
    "SampRate=%d\n  X, Y, Z\n0 %d,%d,%d\n1 %d,%d,%d\n2 %d,%d,%d\nbytes: %ld",
    (int)BUFFER_SAMPLE_RATE,
    data_buff[0],
    data_buff[1],
    data_buff[2],
    data_buff[3],
    data_buff[4],
    data_buff[5],
    data_buff[6],
    data_buff[7],
    data_buff[8],
    totalBytes
  );
  text_layer_set_text(text_layer, s_buffer);
}

// ================================================================
// wearscript excerpts for quick reference
// ================================================================

// static void handle_accel_data(AccelData *data, uint32_t num_samples) {
//   simply_msg_accel_data(data, num_samples, TRANSACTION_ID_INVALID);
// }

// bool simply_msg_accel_data(AccelData *data, uint32_t num_samples, int32_t transaction_id) {
//   DictionaryIterator *iter = NULL;
//   if (app_message_outbox_begin(&iter) != APP_MSG_OK) {
//     return false;
//   }
//   dict_write_uint8(iter, 0, SimplyACmd_accelData);
//   if (transaction_id >= 0) {
//     dict_write_int32(iter, 1, transaction_id);
//   }
//   dict_write_uint8(iter, 2, num_samples);
//   dict_write_data(iter, 3, (uint8_t*) data, sizeof(*data) * num_samples);
//   return (app_message_outbox_send() == APP_MSG_OK);
// }

// ================================================================
// tx result handlers
// ================================================================

void out_sent_handler(DictionaryIterator *sent, void *context) {
    //APP_LOG(APP_LOG_LEVEL_DEBUG, "DICTIONARY SENT SUCCESSFULLY!");
    msg_run = false;
}

void out_failed_handler(DictionaryIterator *failed, AppMessageResult reason, void *context) {
    //APP_LOG(APP_LOG_LEVEL_DEBUG, "DICTIONARY NOT SENT! ERROR!");
   //text_layer_set_text(text_layer, "ERROR!!!!");
    msg_run = false;
}

// ================================================================
// Data sending
// ================================================================

// returns 1 if buffer full, 0 otherwise
uint8_t fill_buffer(AccelRawData* data, uint32_t num_samples) {
  static int8_t shifts[] = {5,2,1,2,5}; // 1/32, 1/4, 1/2, 1/4, 1/32
  static int32_t x_avg, y_avg, z_avg;
  static uint8_t buff_idx = 0;
  for (uint16_t i = 0; i < num_samples; i += 5) {
    x_avg = 0; y_avg = 0; z_avg = 0;
    // it's basically identical to the coeffs for:
    //  scipy.signal.firwin(5, cutoff = 0.2, window = "hamming")

    x_avg +=  data[i+0].x >> shifts[0];
    x_avg += (data[i+1].x >> shifts[1]) - (data[i+1].x >> 6);
    x_avg += (data[i+2].x >> shifts[2]) - (data[i+2].x >> 5);
    x_avg += (data[i+3].x >> shifts[3]) - (data[i+3].x >> 6);
    x_avg +=  data[i+4].x >> shifts[4];

    y_avg +=  data[i+0].y >> shifts[0];
    y_avg += (data[i+1].y >> shifts[1]) - (data[i+1].y >> 6);
    y_avg += (data[i+2].y >> shifts[2]) - (data[i+2].y >> 5);
    y_avg += (data[i+3].y >> shifts[3]) - (data[i+3].y >> 6);
    y_avg +=  data[i+4].y >> shifts[4];

    z_avg +=  data[i+0].z >> shifts[0];
    z_avg += (data[i+1].z >> shifts[1]) - (data[i+1].z >> 6);
    z_avg += (data[i+2].z >> shifts[2]) - (data[i+2].z >> 5);
    z_avg += (data[i+3].z >> shifts[3]) - (data[i+3].z >> 6);
    z_avg +=  data[i+4].z >> shifts[4];

    data_buff[buff_idx++] = quantize(x_avg);
    data_buff[buff_idx++] = quantize(y_avg);
    data_buff[buff_idx++] = quantize(z_avg);

  } //for each sample

  if (buff_idx < BUFFER_LEN) {
    return false;
  }
  buff_idx = 0;
  totalBytes += BUFFER_LEN * sizeof(BUFFER_T);
  return true;
}

bool msg_bytes(BUFFER_T* data, uint32_t length, int32_t transaction_id) {
  static DictionaryIterator *iter = NULL;
  if (app_message_outbox_begin(&iter) != APP_MSG_OK) {
    return false;
  }
  if (transaction_id >= 0) {
    dict_write_int32(iter, TRANSACTION_ID_KEY, transaction_id);
  }
  dict_write_uint8(iter, NUM_BYTES_KEY, length);
  dict_write_data(iter, DATA_KEY, (uint8_t*) data, sizeof(BUFFER_T) * length);
  return (app_message_outbox_send() == APP_MSG_OK);
}

static int32_t packetsSent = 0;
bool send_accel_data() {
  // msg_bytes(data_buff, BUFFER_LEN_WITH_PADDING, packetsSent);
  // return msg_bytes(data_buff, BUFFER_LEN, ++packetsSent);
  return msg_bytes(data_buff, BUFFER_LEN, -1);
}

// ================================================================
// accel data callback
// ================================================================

void accel_data_handler(AccelRawData *data, uint32_t num_samples, uint64_t timestamp) {
  if (fill_buffer(data, num_samples)) {
    send_accel_data();
  }

  //-------------------------------
  // print data
  //-------------------------------
  if (shouldShowAccelData) {
    show_accel_data(data);
  }

  // AccelRawData* d = data;
  // app_message_outbox_begin(&iter);
  // for (uint8_t i = 0; i < num_samples; i++, d++) {
  //   snprintf(xyz_str, 16, "%d,%d,%d", d->x, d->y, d->z);
  //   Tuplet xyzstr_val = TupletCString(i, xyz_str);
  //   dict_write_tuplet(iter, &xyzstr_val);
  // }
  // waiting_data = true;

  // // send dictionary to phone
  // app_message_outbox_send();
}

// ================================================================
// UI Callbacks
// ================================================================

static void select_click_handler(ClickRecognizerRef recognizer, void *context) {
  if (shouldShowAccelData) {
    shouldShowAccelData = 0;
    show_time();
  } else {
    shouldShowAccelData = 1;
  }
}

static void up_click_handler(ClickRecognizerRef recognizer, void *context) {
  // text_layer_set_text(text_layer, "up");
}

static void down_click_handler(ClickRecognizerRef recognizer, void *context) {
  // text_layer_set_text(text_layer, "down");
}

// ================================================================
// Initialization / Destruction
// ================================================================

static void click_config_provider(void *context) {
  window_single_click_subscribe(BUTTON_ID_SELECT, select_click_handler);
  window_single_click_subscribe(BUTTON_ID_UP, up_click_handler);
  window_single_click_subscribe(BUTTON_ID_DOWN, down_click_handler);
}

static void window_load(Window *window) {
  Layer *window_layer = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(window_layer);

  text_layer = text_layer_create(GRect(5, 0, bounds.size.w - 10, bounds.size.h));
  text_layer_set_overflow_mode(text_layer, GTextOverflowModeWordWrap);
  // text_layer_set_text_color(text_layer, GColorWhite);
  // text_layer_set_background_color(text_layer, GColorBlack);
  layer_add_child(window_layer, text_layer_get_layer(text_layer));
}

static void window_unload(Window *window) {
  text_layer_destroy(text_layer);
}

static void init(void) {
  window = window_create();
  window_set_click_config_provider(window, click_config_provider);
  window_set_window_handlers(window, (WindowHandlers) {
    .load = window_load,
    .unload = window_unload,
  });
  const bool animated = true;
  window_stack_push(window, animated);

  // timer
  tick_timer_service_subscribe(MINUTE_UNIT, &handle_tick);

  // accel data
  accel_raw_data_service_subscribe(SAMPLE_BATCH, &accel_data_handler);
  accel_service_set_sampling_rate(SAMPLE_RATE);

  // app messaging
  app_message_register_outbox_sent(out_sent_handler);
  app_message_register_outbox_failed(out_failed_handler);
  app_message_open(INBOUND_SIZE, OUTBOUND_SIZE);

  app_comm_set_sniff_interval(SNIFF_INTERVAL_REDUCED); //faster tx, more power
}

static void deinit(void) {
  data_logging_finish(data_log);
  accel_data_service_unsubscribe();
  tick_timer_service_unsubscribe();
  app_comm_set_sniff_interval(SNIFF_INTERVAL_NORMAL);
  window_destroy(window);
}

// ================================================================
// Main
// ================================================================

int main(void) {
  init();
  APP_LOG(APP_LOG_LEVEL_DEBUG, "Done initializing, pushed window: %p", window);
  app_event_loop();
  deinit();
}
