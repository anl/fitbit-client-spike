#!/usr/bin/env ruby
# coding: utf-8

require 'date'
require 'fitgem'

WEEKDAY_ACTIVITY_TARGET = 0.65
WEEKEND_ACTIVITY_TARGET = 0.30

def daily_target
  case Date.today.wday
  when 0, 6
    WEEKEND_ACTIVITY_TARGET
  else
    WEEKDAY_ACTIVITY_TARGET
  end
end

def get_active_minutes(act_data)
  actv = {}
  actv['fairlyActiveMinutes'] = act_data['summary']['fairlyActiveMinutes']
  actv['lightlyActiveMinutes'] = act_data['summary']['lightlyActiveMinutes']
  actv['veryActiveMinutes'] = act_data['summary']['veryActiveMinutes']
  actv['sedentaryMinutes'] = act_data['summary']['sedentaryMinutes']
  actv['total'] = actv['fairlyActiveMinutes'] + actv['lightlyActiveMinutes'] +
    actv['veryActiveMinutes'] + actv['sedentaryMinutes']
  actv
end

def get_activities(client, date)
  act_data = client.activities_on_date(date)
  actv = get_active_minutes(act_data)
  actv['floors'] = (act_data['summary']['elevation'].to_f / 10).round(0)
  actv['steps'] = act_data['summary']['steps']
  actv['miles'] = get_miles(act_data)
  actv
end

def get_miles(act_data)
  miles = 0
  # rubocop:disable Style/Next
  act_data['summary']['distances'].each do |activity|
    if activity['activity'] == 'total'
      miles = activity['distance']
      break
    end
  end
  # rubocop:enable Style/Next
  miles
end

def percentage(item, total)
  ((item.to_f / total) * 100).round(1)
end

# Given hours and minutes, increment hours by one and set minutes to 0 if
# minutes is 60
def rollover_time(h, m)
  if m == 60
    h += 1
    m = 0
  end
  h = 0 if h == 24
  [h, m]
end

def sleep_start(sleep)
  time = sleep['sleep'][0]['startTime'].split(/T/)[1]
  time.sub(/:00\.000$/, '')
rescue NoMethodError # No sleep data logged
  return '(no data)'
end

def sleep_stop(sleep)
  final_min = sleep['sleep'][0]['minuteData'][-1]['dateTime']
  h, m, _s = final_min.split(/:/).map(&:to_i)
  m += 1
  h, m = rollover_time(h, m)
  format('%02d:%02d', h, m)
rescue NoMethodError # No sleep data logged
  return '(no data)'
end

def target_delta(target, measure, total)
  measure = measure.to_f
  total = total.to_f
  if measure / total < target
    ((target * total - measure) / (1 - target)).round
  else
    -(measure / target - total).round
  end
end

def time_asleep(sleep_records)
  sleep_times = sleep_records['sleep'].map do |sleep_rec|
    sleep_rec['minuteData'].select { |min| min['value'] == '1' }.size
  end
  total_mins = sleep_times.reduce { |a, e| a + e }
  sleep_hours = total_mins / 60
  sleep_mins = total_mins % 60
  sleep_mins = '0' + sleep_mins.to_s if sleep_mins < 10
  "#{sleep_hours}:#{sleep_mins}"
rescue NoMethodError
  return '(no data)'
end

client = Fitgem::Client.new(consumer_key: ENV['FITBIT_CONSUMER_KEY'],
                            consumer_secret: ENV['FITBIT_CONSUMER_SECRET'],
                            token: ENV['FITBIT_TOKEN'],
                            secret: ENV['FITBIT_SECRET'],
                            user_id: ENV['FITBIT_USER_ID'],
                            ssl: true)
activities = get_activities(client, Date.today.to_s)

fairly = activities['fairlyActiveMinutes']
lightly = activities['lightlyActiveMinutes']
very = activities['veryActiveMinutes']
sedentary = activities['sedentaryMinutes']
total = activities['total']

puts "Steps:               #{activities['steps']}"
puts "Floors:              #{activities['floors']}"
puts "Miles:               #{activities['miles']}"
puts

puts "Lightly active:      #{lightly} min (#{percentage(lightly, total)}%)"
puts "Fairly active:       #{fairly} min (#{percentage(fairly, total)}%)"
puts "Very active:         #{very} min (#{percentage(very, total)}%)"
puts "Sedentary:           #{sedentary} min " \
  "(#{percentage(sedentary, total)}%): " \
  "#{target_delta(daily_target, sedentary, total)} min margin"
puts "Total:               #{total} min"
puts

body = client.body_measurements_on_date('today')
puts "Body fat:            #{format('%.1f', body['body']['fat'])}%"

sleep = client.sleep_on_date(Date.today.to_s)
puts "Sleep last night:    #{time_asleep(sleep)} -" \
 " #{sleep_start(sleep)} -> #{sleep_stop(sleep)}"
puts

yesterday = get_activities(client, Date.today.prev_day.to_s)
y_sed_pct = percentage(yesterday['sedentaryMinutes'], yesterday['total'])
puts "Sedentary yesterday: #{y_sed_pct}%"
puts

devices = client.devices
devices.each do |d|
  puts "#{d['deviceVersion']} synced at #{d['lastSyncTime']};" \
    " battery charge is #{d['battery'].downcase}."
end
