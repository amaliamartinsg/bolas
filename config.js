// Conexión con la base de datos (Supabase). Estos dos valores son públicos por diseño:
// la seguridad la dan las reglas del servidor (supabase/schema.sql), no esconder la clave.
window.CONFIG = {
  url: '',      // p. ej. https://abcdxyz.supabase.co
  anonKey: ''   // la clave "anon" / "publishable" del proyecto
};
