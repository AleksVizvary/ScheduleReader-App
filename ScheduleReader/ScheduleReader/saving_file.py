import os
from icalendar import Calendar
from pathlib import Path

def save_file(cal, client, miesiac):
    directory = Path.cwd() / 'icsHolder'
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        pass

    print("Gotowy plik w folderze icsHolder")
    file_name = f"grafik_{miesiac}_{client.replace(" ", "_")}.ics"
    f = open(os.path.join(directory, file_name), 'wb')
    f.write(cal.to_ical())
    f.close()

    e = open(f'icsHolder/{file_name}', 'rb')
    ecal = Calendar.from_ical(e.read())
    e.close()

    return True
