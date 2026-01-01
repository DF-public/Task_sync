/**
 * Logger Configuration
 *
 * Winston-based logger for the MCP server.
 *
 * @license AGPL-3.0
 */

import winston from 'winston';

export function createLogger() {
  const level = process.env.LOG_LEVEL || 'info';

  return winston.createLogger({
    level,
    format: winston.format.combine(
      winston.format.timestamp(),
      winston.format.errors({ stack: true }),
      winston.format.json()
    ),
    defaultMeta: { service: 'vikunja-mcp' },
    transports: [
      // Write to stderr to avoid interfering with MCP stdio transport
      new winston.transports.Console({
        stderrLevels: ['error', 'warn', 'info', 'debug'],
        format: winston.format.combine(
          winston.format.colorize(),
          winston.format.simple()
        ),
      }),
    ],
  });
}
