/** 即刻日志标志：线框笔记本 + 实心圆点，描边规格与全站图标一致（24px 栅格、1.5px 描边）。 */
export function Logo({ size = 24 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="4" y="3" width="16" height="18" rx="3" />
      <path d="M8 8h8M8 12h8M8 16h5" />
      <circle cx="17" cy="17" r="2.5" fill="currentColor" stroke="none" />
    </svg>
  );
}
