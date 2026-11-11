/**
 * HuellApp · Cliente público de Supabase.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Crear el cliente del navegador con la configuración pública del entorno.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Instancia compartida para los flujos de Supabase Auth.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Solo admite configuración pública del navegador. Las claves secretas y de
 * servicio de Supabase nunca deben incorporarse al bundle del frontend.
 */
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabasePublishableKey) {
  throw new Error(
    'Faltan VITE_SUPABASE_URL o VITE_SUPABASE_PUBLISHABLE_KEY.',
  )
}

export const supabase = createClient(
  supabaseUrl,
  supabasePublishableKey,
)