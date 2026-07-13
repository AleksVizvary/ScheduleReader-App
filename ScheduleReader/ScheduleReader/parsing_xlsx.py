import pandas as pd
from classes import *


pd.set_option('display.max_columns', 500)
pd.set_option('display.max_rows', 500)

# We're walking columns and checking cells:
# When cell's a date we start adding data to day dict;
# After we found another date-cell, we're creating a new day dict;
def parse_pandas_to_dict(schedule_xslx, employee_list):
    schedule_list = {}
    present_day = 0

    for col in schedule_xslx.columns:
        for idx, row in schedule_xslx.iterrows():
            cell = Cell(schedule_xslx.loc[idx, col])
            employee = cell.what_employee(employee_list, row)
            if cell.is_time():
                schedule_list[present_day][employee] = cell.get_time()


            # Checking if cell I am in now is a date cell
            # If yes, that means a new day has started
            if cell.is_date():
                present_day = cell.date()
                schedule_list[present_day] = {f'{person}':"wolne" for person in employee_list}


    return schedule_list





