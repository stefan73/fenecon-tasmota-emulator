# Tasmota/Berry Shelly-Emulator fuer FENECON.
# Nutzt Tasmota-Energie- und Statusdaten soweit verfuegbar und erzeugt die noetigen Shelly Endpunkte.

import webserver
import string

class FeneconShellyEmulator
  var device_name
  var model
  var app
  var firmware_version
  var mac
  var device_id
  var power_w
  var energy_wh
  var previous_energy_wh
  var minute_buckets
  var minute_ts
  var uptime_seconds
  var tracked_minute
  var voltage_v
  var frequency_hz
  var power_factor
  var source
  var sta_ip
  var wifi_status
  var wifi_ssid
  var wifi_bssid
  var wifi_rssi
  var mqtt_connected
  var last_status_refresh
  var temperature_c
  var overpower_limit_w

  def init()
    self.device_name = "Virtual Plug S Gen3"
    self.model = "S3PL-00112EU"
    self.app = "PlugSG3"
    self.firmware_version = "0.0.7-mvp"
    self.mac = "E86BEAE6CAFE"
    self.device_id = "shellyplugsg3-" + self.mac
    self.power_w = 0.0
    self.energy_wh = 0.0
    self.previous_energy_wh = nil
    self.minute_buckets = [0.0, 0.0, 0.0]
    self.minute_ts = 0
    self.uptime_seconds = 0
    self.tracked_minute = 0
    self.voltage_v = 230.0
    self.frequency_hz = 50.0
    self.power_factor = 1.0
    self.source = "manual"
    self.sta_ip = ""
    self.wifi_status = "unknown"
    self.wifi_ssid = ""
    self.wifi_bssid = ""
    self.wifi_rssi = -100
    self.mqtt_connected = false
    self.last_status_refresh = -999
    self.temperature_c = 32.0
    self.overpower_limit_w = 20000.0
  end

  def web_add_handler()
    webserver.on("/shelly", /-> self.handle_shelly(), webserver.HTTP_GET)
    webserver.on("/status", /-> self.handle_legacy_status(), webserver.HTTP_GET)
    webserver.on("/meter/0", /-> self.handle_meter(), webserver.HTTP_GET)
    webserver.on("/relay/0", /-> self.handle_relay(), webserver.HTTP_GET)
    webserver.on("/rpc/Shelly.GetDeviceInfo", /-> self.handle_device_info(), webserver.HTTP_GET)
    webserver.on("/rpc/Shelly.GetStatus", /-> self.handle_status(), webserver.HTTP_GET)
    webserver.on("/rpc/Switch.GetStatus", /-> self.handle_switch_status(), webserver.HTTP_GET)
  end

  def every_second()
    self.uptime_seconds += 1
    self.minute_ts = self.uptime_seconds
    self.sync_from_energy_module()
    self.refresh_runtime_status(false)
    self.ensure_minute_window()
  end

  def refresh_runtime_status(force)
    if !force && (self.uptime_seconds - self.last_status_refresh) < 10
      return
    end

    var status = tasmota.cmd("Status 0", true)
    self.last_status_refresh = self.uptime_seconds

    if status == nil
      return
    end

    var statusnet = self.map_get(status, "StatusNET")
    if statusnet != nil
      var statusnet_mac = self.map_get(statusnet, "Mac")
      if statusnet_mac != nil
        self.mac = string.replace(statusnet_mac, ":", "")
        self.device_id = "shellyplugsg3-" + self.mac
      end

      var ip_addr = self.map_get(statusnet, "IPAddress")
      if ip_addr != nil
        self.sta_ip = ip_addr
      end
    end

    var statussts = self.map_get(status, "StatusSTS")
    if statussts != nil
      var uptime = self.map_get(statussts, "UptimeSec")
      if uptime != nil
        self.uptime_seconds = uptime
        self.minute_ts = self.uptime_seconds
      end

      var mqtt_count_sts = self.map_get(statussts, "MqttCount")
      if mqtt_count_sts != nil
        self.mqtt_connected = mqtt_count_sts > 0
      end

      var wifi = self.map_get(statussts, "Wifi")
      if wifi != nil
        var ssid = self.map_get(wifi, "SSId")
        if ssid != nil
          self.wifi_ssid = ssid
        end

        var bssid = self.map_get(wifi, "BSSId")
        if bssid != nil
          self.wifi_bssid = bssid
        end

        var rssi = self.map_get(wifi, "RSSI")
        if rssi != nil
          self.wifi_rssi = rssi
          if rssi > 0
            self.wifi_status = "got ip"
          end
        end
      end
    end

    var statusmqt = self.map_get(status, "StatusMQT")
    if statusmqt != nil
      var mqtt_count = self.map_get(statusmqt, "MqttCount")
      if mqtt_count != nil
        self.mqtt_connected = mqtt_count > 0
      else
        var mqtt_host = self.map_get(statusmqt, "MqttHost")
        if mqtt_host != nil && mqtt_host != "" && mqtt_host != "0.0.0.0"
          self.mqtt_connected = true
        end
      end
    end

  end
  def sync_from_energy_module()
    var new_source = self.source

    if energy.active_power != nil
      self.power_w = energy.active_power
      new_source = "tasmota-energy"
    end

    if energy.voltage != nil && energy.voltage > 0
      self.voltage_v = energy.voltage
    end

    if energy.frequency != nil && energy.frequency > 0
      self.frequency_hz = energy.frequency
    end

    if energy.power_factor != nil && energy.power_factor > 0
      self.power_factor = energy.power_factor
    end

    if energy.total != nil && energy.total >= 0
      self.set_energy_wh(energy.total * 1000.0)
      new_source = "tasmota-energy"
    end

    self.source = new_source
  end

  def set_energy_wh(current_energy_wh)
    self.ensure_minute_window()

    if self.previous_energy_wh != nil && current_energy_wh >= self.previous_energy_wh
      var delta_wh = current_energy_wh - self.previous_energy_wh
      self.minute_buckets[2] = self.minute_buckets[2] + (delta_wh * 60.0)
    end

    self.previous_energy_wh = current_energy_wh
    self.energy_wh = current_energy_wh
  end

  def ensure_minute_window()
    var now_minute = self.uptime_seconds / 60
    while self.tracked_minute < now_minute
      self.minute_buckets[0] = self.minute_buckets[1]
      self.minute_buckets[1] = self.minute_buckets[2]
      self.minute_buckets[2] = 0.0
      self.tracked_minute += 1
    end
  end

  def handle_shelly()
    self.refresh_runtime_status(true)
    self.send_json(self.build_shelly_info_json())
  end

  def handle_device_info()
    self.refresh_runtime_status(true)
    self.send_json(self.build_shelly_info_json())
  end

  def handle_status()
    self.refresh_runtime_status(true)
    self.send_json(self.build_status_json())
  end

  def handle_switch_status()
    self.refresh_runtime_status(true)
    self.send_json(self.build_switch_status_json())
  end

  def handle_legacy_status()
    self.refresh_runtime_status(true)
    self.send_json(self.build_legacy_status_json())
  end

  def handle_meter()
    self.refresh_runtime_status(true)
    self.send_json(self.build_meter_json())
  end

  def handle_relay()
    self.refresh_runtime_status(true)
    self.send_json(self.build_relay_json())
  end

  def send_json(payload)
    webserver.content_open(200, "application/json")
    webserver.content_send(payload)
    webserver.content_close()
  end

  def build_shelly_info_json()
    return string.format(
      "{\"id\":\"%s\",\"mac\":\"%s\",\"model\":\"%s\",\"gen\":3,\"fw_id\":\"tasmota/%s\",\"ver\":\"%s\",\"app\":\"%s\",\"auth_en\":false,\"auth_domain\":null}",
      self.device_id,
      self.mac,
      self.model,
      self.firmware_version,
      self.firmware_version,
      self.app
    )
  end

  def build_status_json()
    return string.format(
      "{\"ble\":{},\"cloud\":{\"connected\":false},\"sys\":{\"mac\":\"%s\",\"restart_required\":false,\"time\":\"00:00\",\"unixtime\":%i,\"last_sync_ts\":%i,\"uptime\":%i,\"ram_size\":262144,\"ram_free\":180224,\"fs_size\":524288,\"fs_free\":393216,\"cfg_rev\":1,\"kvs_rev\":1,\"schedule_rev\":0,\"webhook_rev\":0,\"btrelay_rev\":0,\"available_updates\":{}},\"wifi\":{\"sta_ip\":\"%s\",\"status\":\"%s\",\"ssid\":\"%s\",\"rssi\":%i,\"bssid\":\"%s\"},\"mqtt\":{\"connected\":%s},\"ws\":{\"connected\":false},\"switch:0\":%s}",
      self.mac,
      self.uptime_seconds,
      self.uptime_seconds,
      self.uptime_seconds,
      self.sta_ip,
      self.wifi_status,
      self.wifi_ssid,
      self.wifi_rssi,
      self.wifi_bssid,
      self.bool_json(self.mqtt_connected),
      self.build_switch_status_json()
    )
  end

  def build_switch_status_json()
    var current_a = 0.0
    if self.voltage_v > 0
      current_a = self.power_w / self.voltage_v
    end

    return string.format(
      "{\"id\":0,\"source\":\"%s\",\"output\":true,\"timer_started_at\":%i,\"timer_duration\":60,\"apower\":%.3f,\"voltage\":%.1f,\"current\":%.3f,\"pf\":%.3f,\"freq\":%.1f,\"aenergy\":{\"total\":%.3f,\"by_minute\":[%.3f,%.3f,%.3f],\"minute_ts\":%i},\"ret_aenergy\":{\"total\":0,\"by_minute\":[0.0,0.0,0.0],\"minute_ts\":%i},\"temperature\":{\"tC\":%.1f,\"tF\":%.1f}}",
      self.source,
      self.uptime_seconds,
      self.power_w,
      self.voltage_v,
      current_a,
      self.power_factor,
      self.frequency_hz,
      self.energy_wh,
      self.minute_buckets[0],
      self.minute_buckets[1],
      self.minute_buckets[2],
      self.minute_ts,
      self.minute_ts,
      self.temperature_c,
      (self.temperature_c * 9.0 / 5.0) + 32.0
    )
  end

  def build_legacy_status_json()
    var temp_f = (self.temperature_c * 9.0 / 5.0) + 32.0
    return string.format(
      "{\"relays\":[%s],\"meters\":[%s],\"temperature\":%.1f,\"overtemperature\":false,\"tmp\":{\"tC\":%.1f,\"tF\":%.1f,\"is_valid\":true}}",
      self.build_relay_json(),
      self.build_meter_json(),
      self.temperature_c,
      self.temperature_c,
      temp_f
    )
  end

  def build_meter_json()
    return string.format(
      "{\"power\":%.3f,\"overpower\":%.1f,\"is_valid\":true,\"timestamp\":%i,\"counters\":[%.3f,%.3f,%.3f],\"total\":%.3f}",
      self.power_w,
      self.overpower_limit_w,
      self.uptime_seconds,
      self.minute_buckets[0],
      self.minute_buckets[1],
      self.minute_buckets[2],
      self.energy_wh * 60.0
    )
  end

  def build_relay_json()
    return "{\"ison\":true,\"has_timer\":false,\"timer_started\":0,\"timer_duration\":0,\"timer_remaining\":0,\"overpower\":false,\"source\":\"http\"}"
  end

  def bool_json(value)
    if value
      return "true"
    end
    return "false"
  end

  def map_get(map_obj, key)
    if map_obj == nil
      return nil
    end

    try
      return map_obj[key]
    except .. as _
      return nil
    end
  end
end

var emulator = FeneconShellyEmulator()
tasmota.add_driver(emulator)


