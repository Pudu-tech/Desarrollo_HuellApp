import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'
import type { ExportFormat, ExportTable } from '../../utils/queryExport'
import '../../styles/export.css'

export default function ExportButton({ disabled, prepare, onBusyChange }: { disabled: boolean; prepare: () => Promise<ExportTable>; onBusyChange?: (busy: boolean) => void }) {
  const container = useRef<HTMLDivElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  const options = useRef<Array<HTMLButtonElement | null>>([])
  const initialFocus = useRef(0)
  const menuId = useId()
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const working = useRef(false)
  const restoreFocus = useRef(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  useEffect(() => {
    if (!busy && restoreFocus.current) {
      restoreFocus.current = false
      trigger.current?.focus()
    }
  }, [busy])
  useEffect(() => {
    if (!open && !error) return
    if (open) options.current[initialFocus.current]?.focus()
    const closeOutside = (event: Event) => {
      if (!container.current?.contains(event.target as Node)) { setOpen(false); setError('') }
    }
    document.addEventListener('pointerdown', closeOutside)
    document.addEventListener('focusin', closeOutside)
    return () => {
      document.removeEventListener('pointerdown', closeOutside)
      document.removeEventListener('focusin', closeOutside)
    }
  }, [open, error])

  function keyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'Escape') {
      setOpen(false); setError(''); trigger.current?.focus(); event.stopPropagation()
    } else if (event.key === 'Tab') {
      setOpen(false)
    } else if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key) && !disabled && !busy) {
      event.preventDefault()
      const index = options.current.findIndex(option => option === document.activeElement)
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + 2) % 2
      initialFocus.current = !open && event.key === 'ArrowUp' ? 1 : next
      if (open) options.current[next]?.focus()
      else { setError(''); setOpen(true) }
    }
  }
  async function run(format: ExportFormat) {
    if (working.current) return
    working.current = true
    restoreFocus.current = true
    setBusy(true); setOpen(false); setError(''); setNotice(''); onBusyChange?.(true)
    try {
      const table = await prepare()
      const { downloadTable } = await import('../../utils/queryExport')
      await downloadTable(table, format)
      setNotice(`Descarga ${format === 'xlsx' ? 'Excel' : 'PDF'} preparada: ${table.rows.length} registros.`)
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible exportar. Vuelve a intentarlo.') }
    finally { working.current = false; setBusy(false); onBusyChange?.(false) }
  }
  return <div className="query-export" ref={container} onKeyDown={keyDown}>
    <button ref={trigger} type="button" className="query-export-trigger" aria-haspopup="menu" aria-expanded={open && !disabled} aria-controls={menuId} disabled={disabled || busy} onClick={() => { initialFocus.current = 0; setError(''); setNotice(''); setOpen(!open) }}>
      {busy ? 'Preparando…' : 'Exportar'} <span aria-hidden="true">▾</span>
    </button>
    <span className="query-export-announcement" role="status">{busy ? 'Preparando la descarga…' : notice}</span>
    {open && !disabled && <div id={menuId} className="query-export-menu" role="menu" aria-label="Formato de exportación">
      <button ref={element => { options.current[0] = element }} type="button" role="menuitem" tabIndex={-1} className="query-export-excel" onClick={() => void run('xlsx')}>Excel (.xlsx)</button>
      <button ref={element => { options.current[1] = element }} type="button" role="menuitem" tabIndex={-1} className="query-export-pdf" onClick={() => void run('pdf')}>PDF</button>
    </div>}
    {error && <div className="query-export-error" role="alert">{error}</div>}
  </div>
}
