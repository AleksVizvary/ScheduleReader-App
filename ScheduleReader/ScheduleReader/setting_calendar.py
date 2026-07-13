from icalendar import Calendar, Event, vText
import datetime
def is_there_boss(my_shift, people_on_shift, boss_name):
    for shift in people_on_shift:

        if (shift[1][0] == my_shift[0] or shift[1][1] == my_shift[1]) and shift[0] == boss_name:
            return True
    return False

# At this point we have a dictionary of {date: day_info};
# We're extracting info about:
# 1. Client's shift --> my_shift
# 2. How's the others day looks like --> description
def create_description(day, client, boss_name):
    description = ''

    my_shift = []
    those_working = []
    those_having_day_off = []

    # We're looping through the dictionary of {date: day_info}:
    # We'll be spliting the day:
    # a) client's shift;
    # b) shift of those whose present in work that day;
    # c) shift of those whose not;
    for name in day:

            hours = day[name]
            if name != client and not isinstance(hours, str):
                those_working.append([name, hours])

            elif name == client:
                my_shift = hours
                if hours == 'wolne':
                    return None, None

            elif isinstance(hours, str) and name != client:
                those_having_day_off.append([name, hours])

    is_boss_present = is_there_boss(my_shift, those_working, boss_name)
    # We're sorting the shift of those whose present in work that day;
    those_working.sort(key=lambda x: x[1])
    # And we're changing a shift ifno (hours) format: (datetime, datetime) --> "start-end"
    those_working = [f"{shift[0]}: {shift[1][0].hour}-{shift[1][1].hour}" for shift in those_working]
    those_having_day_off = [f"{shift[0]}: {shift[1]}" for shift in those_having_day_off]

    # We're creating a simple string, with all info about the days shift
    if is_boss_present:
        description = '\tZMIANA Z G\n'
    description += ''.join([f"{shift}\n" for shift in those_working])
    description += ''.join([f"{shift}\n" for shift in those_having_day_off])
    return  my_shift, description


def add_event(start, end, event_name, description, adress):
    event = Event()
    event.add('summary', event_name)
    event.add('dtstart', start)
    event.add('dtend', end)
    event.add('description', description)
    event['location'] = vText(adress)
    return event

def add_days_to_cal(dates_dict, boss_name, client, adress, event_name):
    cal = Calendar()
    cal.add('prodid', '-//My calendar product//example.com//')
    cal.add('version', '2.0')
    for date, record in dates_dict.items():

            my_shift, description = create_description(record, client, boss_name)
            if my_shift is not None:
                start = datetime.datetime(date.year, date.month, date.day, my_shift[0].hour, my_shift[0].minute)
                end = datetime.datetime(date.year, date.month, date.day, my_shift[1].hour, my_shift[1].minute)

                event = add_event(start, end, event_name, description, adress)
                cal.add_component(event)

    return cal
