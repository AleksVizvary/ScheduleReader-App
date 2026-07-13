import datetime, re
class Cell:
    def __init__(self, inside):
        self.inside = inside

    def is_time(self):
        if type(self.inside) is str:
            if re.match(r'^\d{1,2}-\d{1,2}', self.inside) or (re.match(r'^\d{1,2},-\d{1,2}', self.inside)):
                return True

        return False
    def is_urlop(self):
        if type(self.inside) is str:
            if self.inside == 'u':
                return True
        return False

    def get_time(self):
        start, end = re.split(r'-|,-', self.inside)
        start = start.replace(',', '')
        end = end.replace(',', '')
        return [datetime.time(int(start), 0), datetime.time(int(end), 0)]

    def is_date(self):
        if isinstance(self.inside, (datetime.datetime, datetime.date)):
            return True
        return False

    def date(self):
        # print(type(self.inside))
        print(self.inside)
        return self.inside

    # After finding out cells is in time format, it's being checked on what employee does this cell refers to:
    def what_employee(self, employee_list, row):
        for employee in employee_list:
            if employee in row.values:
                return employee
        return None

    def __repr__(self):
        return str(self.inside)
