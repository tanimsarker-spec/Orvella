/** Sends email through SMTP (nodemailer) when configured; in development it prints to the console instead. */
export function createMailer(config) {
  if (!config.smtpHost) {
    return {
      enabled: false,
      async send({ to, subject, text }) {
        console.log(`[mail not configured] to=${to} subject=${subject}\n${text}`);
      },
    };
  }
  return {
    enabled: true,
    async send(message) {
      const nodemailer = (await import('nodemailer')).default;
      const transport = nodemailer.createTransport({
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpPort === 465,
        auth: config.smtpUser ? { user: config.smtpUser, pass: config.smtpPass } : undefined,
      });
      await transport.sendMail({ from: config.mailFrom, ...message });
    },
  };
}
