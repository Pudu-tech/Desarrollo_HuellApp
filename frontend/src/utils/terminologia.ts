/** Actualiza textos históricos al mostrarlos sin modificar los registros guardados. */
export function textoInstancias(text: string | null | undefined): string {
  return (text ?? '').replace(/\basignaci[oó]n(?:es)?\b/gi, (word) => {
    const value = word.toLowerCase().endsWith('es') ? 'instancias' : 'instancia'
    if (word === word.toUpperCase()) return value.toUpperCase()
    return word[0] === word[0].toUpperCase() ? value[0].toUpperCase() + value.slice(1) : value
  })
}
