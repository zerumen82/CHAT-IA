import re
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext, filedialog
import requests
import base64
import threading
from PIL import Image, ImageTk

# Configuración estilo Bootstrap
COLORS = {
    "primary": "#007BFF",
    "user_bg": "#2d6099",  # Azul oscuro para mensajes del usuario
    "user_text": "#ffffff",  # Texto blanco para mensajes del usuario
    "bot_bg": "#1e1e1e",  # Gris oscuro para mensajes del bot
    "bot_text": "#ffffff",
    "but_bg": "#6f6f6c",
    "code_bg": "#2d2d2d",        # Fondo para bloques de código
    "text_fg": "#ffffff",        # Color de texto principal
    "code_fg": "#d4d4d4",        # Color de texto en bloques de código
    "button_bg": "#3a3a3a",      # Fondo de botones
    "danger": "#DC3545",         # Color para errores o advertencias
    "scroll_bg": "#404040",      # Fondo de la barra de scroll
    "scroll_arrow": "#808080",   # Color de las flechas del scroll
    "input_bg": "#686868",       # Fondo del campo de entrada de texto
    "header_bg": "#686868",      # Fondo del encabezado
    "footer_bg": "#686868",       # Fondo del pie de página
    "BG": "#686868"
}

FONTS = {
    "text": ("Segoe UI", 13),
    "bold": ("Segoe UI", 13, "bold"),
    "italic": ("Segoe UI", 13, "italic"),
    "code": ("Consolas", 12),
    "small": ("Segoe UI", 11)
}

class ChatApp:
    def __init__(self, root):
        self.copy_icon = Image.open("D:\PROJECTS\OLLAMACHATI\dist\CHAT-IA\_internal\copil.png")
        self.copy_icon.thumbnail((20, 20))
        self.copy_icon = ImageTk.PhotoImage(self.copy_icon)
        self.root = root
        self.current_images = []
        self.available_models = []
        self.selected_model = tk.StringVar()
        self.abort_request = False
        self.active_thread = None
        self.setup_ui()
        self.setup_styles()
        self.setup_bindings()
        self.load_models()

    def setup_ui(self):
        self.root.title("Chat-IA")
        self.root.iconphoto(False, tk.PhotoImage(file="D:\PROJECTS\OLLAMACHATI\dist\CHAT-IA\_internal\mini.png"))
        self.root.geometry("1700x900")
        self.root.configure(bg=COLORS["header_bg"])
        self.root.resizable(False, False)  # Deshabilitar maximizar

        # Header con selector de modelos
        header = ttk.Frame(self.root)
        header.pack(fill=tk.X, padx=10, pady=5)

        ttk.Label(header, text="Modelo:", font=FONTS["bold"]).pack(side=tk.LEFT)
        self.model_dropdown = ttk.Combobox(header, textvariable=self.selected_model, state="readonly")
        self.model_dropdown.pack(side=tk.LEFT, padx=5)

        ttk.Button(header, text="↻", width=3, command=self.load_models).pack(side=tk.LEFT)

        self.chat_container = tk.Canvas(self.root, bg="#1e1e1e", highlightthickness=0)
        self.chat_scroll = ttk.Scrollbar(self.root, orient="vertical", command=self.chat_container.yview)
        self.chat_container.configure(yscrollcommand=self.chat_scroll.set)
        self.chat_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.chat_container.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        self.chat_frame = ttk.Frame(self.chat_container)
        self.chat_window = self.chat_container.create_window((0, 0), window=self.chat_frame, anchor="nw")

        # Panel inferior
        footer = ttk.Frame(self.root)
        footer.configure(style="TFrame")
        footer.pack(fill=tk.X, padx=10, pady=10)

        # Botón de adjuntar imagen
        self.btn_attach = ttk.Button(footer, text="📷 Imagen", command=self.attach_image)
        self.btn_attach.pack(side=tk.LEFT, padx=5)

        # Entrada de texto
        self.input_field = tk.Text(footer, height=4, wrap=tk.WORD, bg=COLORS["code_bg"],
                                   fg=COLORS["text_fg"], font=FONTS["text"], relief="flat")
        self.input_field.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5)

        # Botones de acción
        btn_frame = ttk.Frame(footer)
        btn_frame.configure(style="TFrame")
        btn_frame.pack(side=tk.RIGHT)

        self.btn_send = ttk.Button(btn_frame, text="Enviar", command=self.send_message)
        self.btn_send.pack(pady=2, fill=tk.X)

        self.btn_stop = ttk.Button(btn_frame, text="⏹ Detener", command=self.stop_request,
                                   state="disabled", style="Danger.TButton")
        self.btn_stop.pack(pady=2, fill=tk.X)

        # Animación de pensando
        self.thinking_label = ttk.Label(self.root, text="", font=FONTS["small"])
        self.loading_dots = 0

    def setup_bindings(self):
        # Enlace de teclado para Enter/Shift+Enter
        self.input_field.bind("<Return>", self.on_enter)
        self.input_field.bind("<Shift-Return>", lambda e: self.input_field.insert(tk.END, "\n"))

        self.chat_container.bind("<Configure>", self.on_canvas_configure)
        self.chat_frame.bind("<Configure>", self.on_frame_configure)

        # Enlace para copiar con Ctrl+C
        self.root.bind_all("<Control-c>", self.copy_from_chat)

        # Enlace para detener con Escape
        self.root.bind("<Escape>", lambda e: self.stop_request())

    def on_canvas_configure(self, event):
        self.chat_container.itemconfig(self.chat_window, width=event.width)

    def on_frame_configure(self, event):
        self.chat_container.configure(scrollregion=self.chat_container.bbox("all"))

    def create_message_bubble(self, text, is_user=True):
        frame = ttk.Frame(self.chat_frame, style="User.TFrame" if is_user else "Bot.TFrame")
        frame.pack(pady=10, padx=20, anchor=tk.E if is_user else tk.W)

        if is_user:
            self.create_text_block(frame, text, is_user)
        else:
            self.process_content(frame, text, is_user)

        self.chat_container.update_idletasks()
        self.chat_container.yview_moveto(1.0)

    def setup_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TButton", background=COLORS["button_bg"], foreground=COLORS["text_fg"])
        style.map("TButton",
                  background=[("active", COLORS["button_bg"]), ("disabled", "#505050")],
                  foreground=[("active", "white"), ("disabled", "#808080")])

        style.configure("Danger.TButton", background=COLORS["danger"], foreground="white")
        style.map("Danger.TButton",
                  background=[("active", COLORS["danger"]), ("disabled", "#8B0000")])

        style.configure("TCombobox", fieldbackground=COLORS["code_bg"], background=COLORS["code_bg"],foreground=COLORS["text_fg"])
        style.map("TCombobox", fieldbackground=[("focus", COLORS["code_bg"])])
        style.configure("TFrame", background=COLORS["bot_bg"])
        style.configure("TLabel", background=COLORS["bot_bg"], foreground=COLORS["text_fg"])
        style.configure("Error.TFrame", background=COLORS["danger"])

        style = ttk.Style()
        style.configure("Think.TFrame",
                        background=COLORS["code_bg"],
                        borderwidth=1,
                        relief="solid")

        style.configure("Think.TButton",
                        background=COLORS["code_bg"],
                        foreground=COLORS["text_fg"],
                        font=FONTS["small"],
                        padding=5)

        style.map("Think.TButton",
                  background=[("active", COLORS["code_bg"])],
                  relief=[("active", "sunken")])

        style.configure("ThinkContent.TFrame",
                        background=COLORS["code_bg"],
                        padding=10)

    def on_enter(self, event):
        if not event.state & 0x1:  # Controlar Enter sin Shift
            self.send_message()
            return "break"

    def copy_from_chat(self, event):
        try:
            widget = self.root.focus_get()
            if isinstance(widget, tk.Text):
                selected = widget.selection_get()
                self.root.clipboard_clear()
                self.root.clipboard_append(selected)
        except tk.TclError:
            pass

    def process_content(self, parent, text, is_user):
        blocks = re.split(r'(```.*?```)', text, flags=re.DOTALL)
        for block in blocks:
            if block.startswith('```') and block.endswith('```'):
                code_content = block[3:-3].strip()
                self.create_code_block(parent, code_content, is_user)
            else:
                self.create_text_block(parent, block, is_user)

    def create_code_block(self, parent, content, is_user):
        code_frame = ttk.Frame(parent, style="Code.TFrame")
        code_frame.pack(fill=tk.X, pady=5)

        code_text = scrolledtext.ScrolledText(code_frame, wrap=tk.NONE,
                                              bg=COLORS["code_bg"], fg=COLORS["code_fg"],
                                              font=FONTS["code"], height=min(15, content.count('\n') + 1))
        code_text.insert(tk.END, content)
        self.apply_syntax_highlighting(code_text)  # Aplicar resaltado de sintaxis
        code_text.configure(state=tk.DISABLED)
        code_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        copy_btn = ttk.Button(code_frame, text="📋", width=3, command=lambda: self.copy_text(content))
        copy_btn.pack(side=tk.RIGHT, padx=5)

    def display_message(self, text, sender):
        """
        Muestra un mensaje en el chat, con soporte para el tag <think> como desplegable.
        """
        is_bot = (sender == "bot")

        if "<think>" in text and "</think>" in text:
            think_match = re.search(r'<think>(.*?)</think>', text, re.DOTALL)
            if think_match:
                think_content = think_match.group(1).strip()
                text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL).strip()

                # Crear burbuja de mensaje del bot
                self.create_message_bubble(text, is_user=False)

                # Crear desplegable
                think_frame = ttk.Frame(self.chat_frame, style="Think.TFrame")
                think_frame.pack(pady=5, padx=20, anchor=tk.W)

                # 1. Crear el botón SIN comando primero
                toggle_button = ttk.Button(
                    think_frame,
                    text="💭 Mostrar pensamiento",
                    style="Think.TButton"
                )

                # 2. Crear el frame de contenido
                content_frame = ttk.Frame(think_frame, style="ThinkContent.TFrame")
                self.create_text_block(content_frame, think_content, is_bot)
                content_frame.pack_forget()

                # 3. Añadir el comando DESPUÉS de crear el botón
                toggle_button.config(command=lambda: self.toggle_think_content(content_frame, toggle_button))

                toggle_button.pack(side=tk.LEFT, padx=5)
        else:
            if text.strip():
                self.create_message_bubble(text, is_bot)

    def toggle_think_content(self, content_frame, toggle_button):
        """
        Alterna la visibilidad del contenido de <think>.
        """
        if content_frame.winfo_ismapped():
            content_frame.pack_forget()
            toggle_button.config(text="💭 Mostrar pensamiento")
        else:
            content_frame.pack(fill=tk.X)
            toggle_button.config(text="💭 Ocultar pensamiento")

    def create_text_block(self, parent, text, is_user):
        text_frame = ttk.Frame(parent)
        text_frame.pack(fill=tk.X, pady=5)

        text_widget = tk.Text(
            text_frame,
            wrap=tk.WORD,
            bg=COLORS["user_bg"] if is_user else COLORS["code_bg"],
            fg=COLORS["user_text"] if is_user else COLORS["code_fg"],
            font=FONTS["text"],
            padx=10,
            pady=5,
            relief="flat",
            height=self.calculate_height(text)
        )
        self.insert_formatted_text(text_widget, text)  # Llamada al formateador
        text_widget.config(state=tk.DISABLED)
        text_widget.pack(fill=tk.X)

    def insert_formatted_text(self, widget, text):
        self.tag_patterns = {
            'bold': (r'\*\*(.*?)\*\*', FONTS["bold"]),
            'italic': (r'\*(.*?)\*', FONTS["italic"]),
            'code': (r'`(.*?)`', FONTS["code"])
        }
        widget.delete("1.0", tk.END)
        widget.mark_set("insert", "1.0")
        for line in text.split('\n'):
            temp_line = line
            for tag, (pattern, font) in self.tag_patterns.items():
                while True:
                    match = re.search(pattern, temp_line)
                    if not match:
                        break
                    before, content, after = (temp_line[:match.start()],
                                              match.group(1),
                                              temp_line[match.end():])
                    widget.insert("insert", before)
                    widget.insert("insert", content, (tag,))
                    temp_line = after
            widget.insert("insert", temp_line + '\n')

        for tag, (_, font) in self.tag_patterns.items():
            widget.tag_configure(tag, font=font)

        self.apply_syntax_highlighting(widget)

    def apply_syntax_highlighting(self, widget):
        keywords = ["def", "class", "import", "from", "return", "if", "else", "elif", "for", "while", "try", "except",
                    "with", "as", "lambda"]
        keyword_pattern = r'\b(' + '|'.join(keywords) + r')\b'
        comment_pattern = r'#.*'
        string_pattern = r'(\".*?\"|\'.*?\')'

        widget.tag_configure("keyword", foreground="blue")
        widget.tag_configure("comment", foreground="green")
        widget.tag_configure("string", foreground="orange")

        for pattern, tag in [(keyword_pattern, "keyword"), (comment_pattern, "comment"), (string_pattern, "string")]:
            start = "1.0"
            while True:
                match = re.search(pattern, widget.get(start, tk.END), re.MULTILINE)
                if not match:
                    break
                start_idx = f"{match.start() + int(start.split('.')[0]) - 1}.{match.start()}"
                end_idx = f"{match.start() + int(start.split('.')[0]) - 1}.{match.end()}"
                widget.tag_add(tag, start_idx, end_idx)
                start = end_idx

    def calculate_height(self, text):
        lines = text.count('\n') + 1
        return min(max(lines, 3), 15)

    def copy_text(self, text):
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def send_message(self):
        user_input = self.input_field.get("1.0", tk.END).strip()
        if not user_input and not self.current_images:
            return

        self.abort_request = False
        self.btn_send.config(state="disabled")
        self.btn_stop.config(state="enabled")
        self.create_message_bubble(user_input, is_user=True)
        self.input_field.delete("1.0", tk.END)
        self.start_thinking_animation()

        self.active_thread = threading.Thread(
            target=self.process_response,
            args=(user_input, [img["base64"] for img in self.current_images]),
            daemon=True
        )
        self.active_thread.start()
        self.current_images.clear()

    def stop_request(self):
        self.abort_request = True
        self.btn_stop.config(state="disabled")
        self.btn_send.config(state="enabled")
        self.stop_thinking_animation()

    def process_response(self, prompt, images):
        try:
            payload = {
                "model": self.selected_model.get(),
                "prompt": prompt,
                "images": images,
                "stream": False
            }

            response = requests.post(
                "http://localhost:11434/api/generate",
                json=payload
            )
            response.raise_for_status()

            if self.abort_request:
                return

            response_text = response.json().get("response", "")
            self.root.after(0, self.display_message, response_text, False)

        except Exception as e:
            if not self.abort_request:
                self.root.after(0, self.show_error, str(e))
        finally:
            self.root.after(0, self.stop_thinking_animation)
            self.root.after(0, lambda: self.btn_send.config(state="enabled"))
            self.root.after(0, lambda: self.btn_stop.config(state="disabled"))

    def start_thinking_animation(self):
        self.loading_dots = 0
        self.thinking_label.pack(side=tk.BOTTOM, fill=tk.X, pady=5)  # Usar pack en lugar de grid
        self.animate_thinking()

    def animate_thinking(self):
        if self.loading_dots < 3:
            self.thinking_label.config(text=f"Generando respuesta{'.' * self.loading_dots}")
            self.loading_dots += 1
            self.root.after(500, self.animate_thinking)

    def stop_thinking_animation(self):
        self.thinking_label.pack_forget()

    def show_error(self, message):
        error_frame = ttk.Frame(self.chat_frame, style="Error.TFrame")
        error_frame.pack(fill=tk.X, padx=20, pady=10)

        ttk.Label(error_frame, text=f"⚠️ Error: {message}", style="Error.TLabel").pack(pady=5)


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

                lbl = ttk.Label(self.root, image=photo)
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


if __name__ == "__main__":
    root = tk.Tk()
    app = ChatApp(root)
    root.mainloop()