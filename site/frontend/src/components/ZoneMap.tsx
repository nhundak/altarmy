import { zoneMapUrl } from '../lib/wow'
import classes from './ZoneMap.module.css'

/** The zone's map with a dot where `name` stands; `x` and `y` are map coordinates (percent). */
export function ZoneMap({ area, x, y, name }: { area: number; x: number; y: number; name: string }) {
  return (
    <div className={classes.map}>
      <img src={zoneMapUrl(area)} alt={`Map: ${name}`} className={classes.image} />
      <span className={classes.dot} style={{ left: `${x}%`, top: `${y}%` }} data-testid="map-dot" />
    </div>
  )
}
