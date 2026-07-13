from tkinter import *

root = Tk("Tests")
root.geometry('720x720')

left_space = Frame(root)
right_space = Frame(root)

left_space.pack(side=LEFT, fill=BOTH, expand=True)
right_space.pack(side=RIGHT, fill=BOTH, expand=True)

dane = Frame(right_space)
workers = Frame(right_space)


root.mainloop()
