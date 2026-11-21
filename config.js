// Conexión con la base de datos (Supabase). Estos dos valores son públicos por diseño:
// la seguridad la dan las reglas del servidor (supabase/schema.sql), no esconder la clave.
window.CONFIG = {
  url: 'https://kpayalbdaxljoemzqynb.supabase.co',      // sin /rest/v1/ al final
  anonKey: 'sb_publishable_JIdnB3RhWGOWz6mFQ8qCjw_aK6x8946'   // clave publishable (pública)
};
