from parsing_xlsx import *
from setting_calendar import *
from saving_file import *
# from open_file import *

event_name = "Praca"
adress = "ul. Pawia 5, 31-154, Kraków, Polska"

def main(i, path=None):
    with open("../EmployeeNamesList.txt", "r") as file:
        employee_list = [p.split(';')for p in file][0]
    boss_name = employee_list[7]
    client = employee_list[i]

    miesiac = 'czerwiec'
    file_name = f"grafik_{miesiac}.xlsx"
    file_path = "DataHolder/" + file_name
    if not path:
        path = Path(__file__).parent.resolve().parent.resolve() / file_path

    schedule_xslx = pd.read_excel(path)
    schedule_list = parse_pandas_to_dict(schedule_xslx, employee_list)

    cal = add_days_to_cal(schedule_list, boss_name, client, adress, event_name)
    save_file(cal, client, miesiac)

path = None
# path = get_path()
main(1, path)



















