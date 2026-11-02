type Located = {
  latitude: string | null
  longitude: string | null
  location_label?: string
  location_area?: string
  location_source?: string
  location_accuracy_m?: number | null
}

function radiusText(metres: number) {
  return metres >= 1000 ? `${Math.round(metres / 100) / 10} km` : `${metres} m`
}

/** Where an alert happened: place name, how precise it is, and the exact spot on a map. */
export function AlertLocation({ alert }: { alert: Located }) {
  if (!alert.latitude || !alert.longitude) {
    return <span className="text-slate-500">Location unavailable</span>
  }
  const isCell = alert.location_source === 'opencellid'
  const place = alert.location_area || alert.location_label
  return (
    <div className="min-w-0">
      {place ? <p className="font-medium text-[var(--color-charcoal)]">{place}</p> : null}
      {isCell ? (
        <p className="text-xs text-slate-500">
          {alert.location_accuracy_m
            ? `Within about ${radiusText(alert.location_accuracy_m)} (cell tower)`
            : 'Approximate (cell tower)'}
        </p>
      ) : alert.location_source === 'gps' ? (
        <p className="text-xs text-slate-500">GPS</p>
      ) : null}
      <a
        className="text-xs text-[var(--color-blue)] underline"
        href={`https://maps.google.com/?q=${alert.latitude},${alert.longitude}`}
        target="_blank"
        rel="noreferrer"
      >
        {place ? 'Open map' : `${alert.latitude}, ${alert.longitude}`}
      </a>
    </div>
  )
}
