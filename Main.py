import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext, filedialog
from tkinter.messagebox import showerror

import requests
import base64
import threading
from PIL import Image, ImageTk
import re
from tkinter import Canvas
# Configuración estilo Bootstrap
COLORS = {
    "primary": "#007BFF",
    "imageBut": "#460a50",
    "sendBut": "#0a501b",
    "stopBut": "#500a12",
    "modelBut": "#50480a",
    "secondary": "#6C757D",
    "success": "#28A745",
    "danger": "#DC3545",
    "light": "#F8F9FA",
    "dark": "#5c5c5c",
    "input_bg": "#252525",
    "bg": "#000000",
    "header_bg": "#000000",
    "footer_bg": "#000000"
}

FONT = ("Tahoma", 12)
FONT_BOLD = ("Tahoma", 12, "bold")
FONT_TEXT = ("Arial", 11)
FONT_CODE = ("Courier New", 10)

class ChatApp:
    def __init__(self, root):
        self.cutAffter=False
        self.root = root
        self.left_row = 0  # Track filas columna izquierda
        self.right_row = 2
        self.current_images = []
        self.available_models = []
        self.btnSend=None
        self.selected_model = tk.StringVar()
        # Cargar el ícono de copiar
        self.copy_icon = Image.open("D:\PROJECTS\OLLAMACHATI\dist\CHAT-IA\_internal\copil.png")
        self.copy_icon.thumbnail((20, 20))
        self.copy_icon = ImageTk.PhotoImage(self.copy_icon)
        self.setup_ui()
        self.load_models()

    def on_chat_resize(self, event):
        """Actualizar contenido al redimensionar ventana"""
        for child in self.chat_area.winfo_children():
            if isinstance(child, tk.Frame):
                # Ajustar ancho del contenedor principal
                child.config(width=event.width)
                for bubble in child.winfo_children():
                    if isinstance(bubble, tk.Frame):
                        # Solo para widgets Text (código formateado)
                        for widget in bubble.winfo_children():
                            if isinstance(widget, tk.Text):
                                # Ajustar ancho del texto (no wraplength)
                                new_width = int(event.width * 0.4) // 7  # Caracteres aproximados
                                widget.config(width=new_width)
    def setup_ui(self):
        self.root.title("Chat-IA")
        self.root.iconphoto(False, tk.PhotoImage(file="D:\PROJECTS\OLLAMACHATI\dist\CHAT-IA\_internal\mini.png"))
        self.root.geometry("1000x700")
        self.root.configure(bg=COLORS["bg"])
        style = ttk.Style()
        style.configure("Chat.TFrame", background=COLORS["bg"])
        # Panel superior
        header = ttk.Frame(self.root, style="Header.TFrame")
        header.pack(fill=tk.X, padx=10, pady=5)
        # Estilos personalizados

        # Selector de modelos
        ttk.Label(header, text="Modelo:", style="Header.TLabel",foreground="white").pack(side=tk.LEFT)
        self.model_dropdown = ttk.Combobox(
            header,
            textvariable=self.selected_model,
            state="readonly"
        )
        self.model_dropdown.pack(side=tk.LEFT, padx=5)

        tk.Button(header,
                  bg=COLORS["modelBut"],
                  fg='white',
                  relief='flat',
                  text="🔄",
                  command=self.load_models,
                  font=FONT_BOLD).pack(side=tk.LEFT)

        # Área de chat
        self.chat_area = scrolledtext.ScrolledText(
            self.root,
            wrap=tk.WORD,
            state="disabled",
            font=FONT,
            bg=COLORS["input_bg"],
            padx=15,
            pady=15
        )
        self.chat_area.bind("<Configure>", self.on_chat_resize)
        self.chat_area.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        self.chat_area.bind("<Control-c>", self.copy_selection)
        # Panel inferior
        footer = ttk.Frame(self.root, style="Footer.TFrame")
        footer.pack(fill=tk.X, padx=10, pady=10)

        # Botón adjuntar imágenes
        btn = tk.Button(footer,
                        bg='#204BC9',
                        fg='white',
                        relief='flat',
                        text='Imagen',
                        command=self.attach_image,
                        font=FONT_BOLD)
        btn.pack(side=tk.LEFT)

        # Entrada de texto
        self.input_field = tk.Text(
            footer,
            height=4,
            font=FONT,
            relief="flat",
            highlightthickness=1,
            bg=COLORS["input_bg"],
            fg="white",
            highlightcolor=COLORS["primary"]

        )
        self.input_field.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)
        self.input_field.bind("<Return>", self.on_enter)

        self.btnSend = tk.Button(footer,
                        bg=COLORS["sendBut"],
                        fg='white',
                        relief='flat',
                        text='Enviar',
                        command=self.send_message,
                        font=FONT_BOLD,
                        state='normal')
        self.btnSend.pack(side=tk.LEFT)
        self.btnStop = tk.Button(footer,
                        bg=COLORS["stopBut"],
                        fg='white',
                        relief='flat',
                        text='Detener',
                        command=self.stop_message,
                        font=FONT_BOLD,
                        state='disabled')
        self.btnStop.pack(side=tk.LEFT)
        # # Botón enviar
        # ttk.Button(
        #     footer,
        #     text="Enviar",
        #     command=self.send_message,
        #     style="Send.TButton"
        # ).pack(side=tk.LEFT)

        # Previsualización imágenes
        self.preview_frame = ttk.Frame(self.root)
        self.preview_frame.pack(fill=tk.X, padx=10, pady=5)
        style = ttk.Style()
        style.configure("Header.TFrame", background=COLORS["header_bg"])
        style.configure("Header.TLabel", background=COLORS["header_bg"], font=FONT_BOLD)
        style.configure("Footer.TFrame", background=COLORS["footer_bg"])
    def copy_selection(self, event):
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.chat_area.selection_get())
        except tk.TclError:
            pass
    def on_enter(self, event):
        if not event.state & (0x0001 | 0x0004):  # Control/Shift
            self.send_message()
            return "break"

    def attach_image(self):
        files = filedialog.askopenfilenames(filetypes=[("Imágenes", "*.png *.jpg *.jpeg")])
        for f in files:
            try:
                img = Image.open(f)
                img.thumbnail((80, 80))
                photo = ImageTk.PhotoImage(img)

                self.current_images.append({
                    "path": f,
                    "base64": base64.b64encode(open(f, "rb").read()).decode("utf-8"),
                    "thumbnail": photo
                })

                lbl = ttk.Label(self.preview_frame, image=photo)
                lbl.image = photo
                lbl.pack(side=tk.LEFT, padx=2)

            except Exception as e:
                messagebox.showerror("Error", f"Error cargando imagen: {str(e)}")

    def load_models(self):
        try:
            response = requests.get("http://localhost:11434/api/tags")
            models = [m["name"] for m in response.json()["models"]]
            self.model_dropdown["values"] = models
            if models:
                self.selected_model.set(models[0])
        except requests.ConnectionError:
            messagebox.showerror("Error", "Ollama no está corriendo")

    def stop_message(self):
        print("Detenido", "El proceso ha sido detenido")
        self.btnSend.config(text='Enviar', state='normal')
        self.btnStop.config(state='disabled')
        self.remove_thinking_label()


    def send_message(self):
        self.btnSend.config(text="Enviando..",state='disabled')
        self.btnStop.config(state='normal')
        text = self.input_field.get("1.0", tk.END).strip()
        if not text and not self.current_images:
            return
        # Mostrar mensaje usuario
        self.display_message(text, "user")

        # Mostrar "pensando" parpadeando
        self.thinking_label = tk.Label(self.chat_area, text="pensando", font=FONT_BOLD, fg=COLORS["primary"], bg=COLORS["input_bg"])
        self.chat_area.window_create(tk.END, window=self.thinking_label)
        self.blink_thinking()
        # Limpiar inputs
        self.input_field.delete("1.0", tk.END)
        self.clear_previews()

        # Enviar en hilo
        self.threadthis=threading.Thread(
            target=self.process_message,
            args=(text, [img["base64"] for img in self.current_images]),
            daemon=True
        ).start()
        self.current_images.clear()

    def blink_thinking(self):
        if self.thinking_label:
            current_color = self.thinking_label.cget("fg")
            next_color = COLORS["primary"] if current_color == COLORS["input_bg"] else COLORS["input_bg"]
            self.thinking_label.config(fg=next_color)
            self.root.after(500, self.blink_thinking)

    def process_message(self, text, images):
        try:
            payload = {
                "model": self.selected_model.get(),
                "prompt": text,
                "images": images,
                "stream": False
            }

            response = requests.post(
                "http://localhost:11434/api/generate",
                json=payload,
                timeout=120
            )
            match_string = "</think>"

            response.raise_for_status()
            response_text = response.json()["response"]
            match_string_len = len(match_string)
            for index, value in enumerate(response_text):
                sub_string = response_text[index:match_string_len + index]
                if sub_string == match_string:
                    print("match string found in main string")
                    indice=index+match_string_len
                    response_text = response_text[indice:]
                    break

            self.root.after(0, self.display_message, response_text, "bot")
            self.root.after(0, self.remove_thinking_label)
        except Exception as e:
            self.root.after(0, self.show_error, str(e))
            self.root.after(0, self.remove_thinking_label)

    def remove_thinking_label(self):
        if self.thinking_label:
            self.thinking_label.destroy()
            self.thinking_label = None

    def display_message(self, text, sender):
        self.chat_area.config(state=tk.NORMAL)
        if self.cutAffter:
            self.chat_area.delete("1.0", tk.END)
            self.cutAffter=False
        # Creamos el contenedor interno una sola vez, organizado en dos columnas
        if not hasattr(self, 'chat_container'):
            self.chat_container = tk.Frame(self.chat_area, bg=COLORS["input_bg"])
            # Se configuran dos columnas que se expanden de forma equitativa
            self.chat_container.grid_columnconfigure(0, weight=1)
            self.chat_container.grid_columnconfigure(1, weight=1)
            self.row_counter = 0
            self.chat_area.window_create(tk.END, window=self.chat_container)

        is_bot = sender == "bot"
        # Definimos el fondo: para el bot (verde claro) y para el usuario (blanco)
        bg_color = "#ccc356" if is_bot else "#b4b9b5"
        fg_color = "black"

        # Creamos la burbuja del mensaje
        bubble = tk.Frame(self.chat_container, bg=bg_color, padx=10, pady=5, relief="solid", bd=1)
        text_widget = tk.Text(
            bubble,
            wrap=tk.WORD,
            width=45,  # Ancho en caracteres (óptimo para lectura)
            height=1,
            bg=bg_color,
            fg=fg_color,
            font=("Segoe UI", 11),
            borderwidth=0,
            highlightthickness=0,
            padx=12,
            pady=8
        )
        # Sistema de tags mejorado
        text_widget.tag_configure("header3",
                                  font=("Arial", 12, "bold"),
                                  foreground="#1A0DAB",
                                  spacing3=8,
                                  lmargin1=10)

        text_widget.tag_configure("bold",
                                  font=("Arial", 11, "bold"))

        text_widget.tag_configure("code",
                                  background="#E8F0FE",
                                  font=("Consolas", 10),
                                  relief="flat",
                                  borderwidth=0)

        text_widget.tag_configure("bullet",
                                  lmargin1=25,
                                  lmargin2=45,
                                  spacing3=5)

        # Procesamiento inteligente del texto
        lines = text.split('\n')
        for line in lines:
            line = line.strip()

            # Encabezados ###
            if line.startswith("###"):
                header_text = line.replace("#", "").strip()
                text_widget.insert(tk.END, f"\n{header_text}\n", "header3")

            # Elementos de lista con •
            elif line.startswith("•"):
                parts = line.split(":", 1)
                if len(parts) > 1:
                    text_widget.insert(tk.END, " " * 4 + "• ", "bullet")
                    text_widget.insert(tk.END, parts[0][1:].strip() + ":\n", "bold")
                    text_widget.insert(tk.END, " " * 8 + parts[1].strip() + "\n", "bullet")
                else:
                    text_widget.insert(tk.END, " " * 4 + line + "\n", "bullet")

            # Código entre `
            elif '`' in line:
                segments = line.split('`')
                for i, seg in enumerate(segments):
                    if i % 2 == 1:  # Texto entre backticks
                        text_widget.insert(tk.END, seg, "code")
                    else:
                        text_widget.insert(tk.END, seg)
                text_widget.insert(tk.END, "\n")

            # Texto normal
            else:
                # Detectar **texto** para negritas
                segments = re.split(r'(\*\*.+?\*\*)', line)
                for seg in segments:
                    if seg.startswith("**") and seg.endswith("**"):
                        text_widget.insert(tk.END, seg[2:-2], "bold")
                    else:
                        text_widget.insert(tk.END, seg)
                text_widget.insert(tk.END, "\n")

        # Ajustes finales
        text_height = text_widget.index('end-1c').split('.')[0]
        text_widget.config(height=text_height, state=tk.DISABLED)
        text_widget.pack(anchor="w" if not is_bot else "e")
        # Si el mensaje es del bot, agregamos el botón de copiar
        if is_bot:
            btn_copy = tk.Label(bubble, image=self.copy_icon, bg=bg_color, cursor="hand2")
            btn_copy.pack(side=tk.RIGHT, padx=5)
            btn_copy.bind("<Button-1>", lambda e: self.copy_text(text))
        else:
            # Si el mensaje es del usuario, agregamos el botón de copiar
            btn_copy = tk.Label(bubble, image=self.copy_icon, bg=bg_color, cursor="hand2")
            btn_copy.pack(side=tk.LEFT, padx=5)
            btn_copy.bind("<Button-1>", lambda e: self.copy_text(text))

        # Colocamos la burbuja en la fila actual:
        # - Si es del usuario, la colocamos en la columna 0 (izquierda), alineada a la izquierda.
        # - Si es del bot, la colocamos en la columna 1 (derecha), alineada a la derecha.
        if is_bot:
            bubble.grid(row=self.row_counter, column=1, sticky="e", padx=(0, 10), pady=5)
        else:
            bubble.grid(row=self.row_counter, column=0, sticky="w", padx=(10, 0), pady=5)

        # Incrementamos el contador de filas para que cada mensaje ocupe su propia línea
        self.row_counter += 1
        self.chat_area.insert(tk.END, "\n")
        self.chat_area.yview(tk.END)
        self.chat_area.config(state=tk.DISABLED)
        self.root.update_idletasks()

    def copy_text(self, text):
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def clear_previews(self):
        for widget in self.preview_frame.winfo_children():
            widget.destroy()

    def show_error(self, error):
        self.chat_area.config(state=tk.NORMAL)
        self.chat_area.insert(tk.END, f"ERROR: {error}\n\n", "error")
        self.chat_area.tag_config("error", foreground=COLORS["danger"])
        self.chat_area.config(state=tk.DISABLED)


if __name__ == "__main__":
    root = tk.Tk()
    app = ChatApp(root)
    root.mainloop()
