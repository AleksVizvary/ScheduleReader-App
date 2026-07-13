import tkinter as tk
from tkinter import filedialog

root = tk.Tk()
root.geometry("+200+100")
root.withdraw()

def get_path():
    path = filedialog.askopenfilename()
    root.destroy()

    return path