// Diagnostico: convierte los resultados de un sondeo en un veredicto y en arreglos copiables. Puro y sin red.
const IPV4 = /^(\d{1,3}\.){3}\d{1,3}$/;
export const SLOW_MS = 600;

const fix = (label, command) => ({ label, command });

/** result: { host, ip, system, cloudflare, google, tcp }, cada uno { ok, ms, error?, value? } */
export function diagnose(r) {
  const { host, system: sys, cloudflare: cf, google: g, tcp } = r;
  const publicOk = cf?.ok || g?.ok;
  const ip = r.ip && IPV4.test(r.ip) ? r.ip : null;

  if (sys.ok && tcp?.ok) {
    const slow = tcp.ms > SLOW_MS || sys.ms > SLOW_MS;
    return { status: slow ? 'slow' : 'ok', severity: slow ? 1 : 0, title: slow ? 'Responde, pero lento.' : 'Todo en orden.', detail: `${host} resuelve en ${sys.ms} ms y conecta en ${tcp.ms} ms.`, fixes: [] };
  }
  if (!sys.ok && publicOk) {
    const fixes = [
      fix('Vaciar la caché DNS del sistema (pide contraseña)', 'sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'),
      fix('Comprobar con un DNS público', `dig +short ${host} @1.1.1.1`),
    ];
    if (ip) {
      fixes.push(fix('Saltarte el DNS al subir con git', `git -c http.curloptResolve=${host}:443:${ip} push`));
      fixes.push(fix('Saltarte el DNS con curl', `curl --resolve ${host}:443:${ip} https://${host}`));
    }
    return { status: 'dns_local', severity: 2, title: 'El DNS de tu Mac no resuelve este nombre.', detail: `${host} sí resuelve en DNS públicos (${cf?.ok ? 'Cloudflare' : 'Google'}), pero no con el DNS del sistema. Suele ser una caché atascada, un VPN o un filtro de DNS.`, fixes };
  }
  if (!sys.ok && !publicOk) {
    return { status: 'dns_total', severity: 3, title: 'No resuelve en ningún DNS.', detail: `ni el DNS del sistema ni Cloudflare ni Google resuelven ${host}: probablemente no tienes red o el dominio no existe.`, fixes: [fix('Comprobar que hay salida a internet', 'ping -c 2 1.1.1.1'), fix('Ver el Wi-Fi actual', 'networksetup -getairportnetwork en0')] };
  }
  if (!tcp?.ok) {
    return { status: 'tcp', severity: 2, title: 'Resuelve, pero no conecta al puerto 443.', detail: `${host} resuelve a ${ip ?? 'una IP'}, pero la conexión falla (${tcp?.error ?? 'sin respuesta'}). Puede ser un firewall, un VPN o que el servicio esté caído.`, fixes: ip ? [fix('Probar la conexión a mano', `nc -vz ${ip} 443`)] : [] };
  }
  return { status: 'unknown', severity: 1, title: 'Resultado ambiguo.', detail: 'Repite el sondeo.', fixes: [] };
}
