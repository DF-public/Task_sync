/**
 * Vikunja MCP Server
 *
 * Model Context Protocol server for Vikunja task management integration.
 * Enables Claude Code to interact with Vikunja tasks, projects, and labels.
 *
 * @license AGPL-3.0
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { VikunjaClient } from './vikunja-client.js';
import { createLogger } from './logger.js';

const logger = createLogger();

// Initialize Vikunja client
const vikunjaClient = new VikunjaClient({
  baseUrl: process.env.VIKUNJA_API_URL || 'http://localhost:3456/api/v1',
  token: process.env.VIKUNJA_API_TOKEN || '',
});

// Create MCP server
const server = new Server(
  {
    name: 'vikunja-mcp',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// =============================================================================
// Tool Definitions
// =============================================================================

const TOOLS = [
  {
    name: 'vikunja_list_projects',
    description: 'List all projects in Vikunja',
    inputSchema: {
      type: 'object',
      properties: {},
      required: [],
    },
  },
  {
    name: 'vikunja_list_tasks',
    description: 'List tasks from a specific project or all tasks',
    inputSchema: {
      type: 'object',
      properties: {
        project_id: {
          type: 'number',
          description: 'Project ID to filter tasks (optional)',
        },
        done: {
          type: 'boolean',
          description: 'Filter by completion status (optional)',
        },
      },
      required: [],
    },
  },
  {
    name: 'vikunja_create_task',
    description: 'Create a new task in Vikunja',
    inputSchema: {
      type: 'object',
      properties: {
        title: {
          type: 'string',
          description: 'Task title',
        },
        project_id: {
          type: 'number',
          description: 'Project ID to add the task to',
        },
        description: {
          type: 'string',
          description: 'Task description (optional)',
        },
        priority: {
          type: 'number',
          description: 'Priority level 1-5 (optional)',
        },
        due_date: {
          type: 'string',
          description: 'Due date in ISO format (optional)',
        },
      },
      required: ['title', 'project_id'],
    },
  },
  {
    name: 'vikunja_update_task',
    description: 'Update an existing task',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: {
          type: 'number',
          description: 'Task ID to update',
        },
        title: {
          type: 'string',
          description: 'New task title (optional)',
        },
        description: {
          type: 'string',
          description: 'New task description (optional)',
        },
        done: {
          type: 'boolean',
          description: 'Mark as complete/incomplete (optional)',
        },
        priority: {
          type: 'number',
          description: 'New priority level (optional)',
        },
      },
      required: ['task_id'],
    },
  },
  {
    name: 'vikunja_complete_task',
    description: 'Mark a task as complete',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: {
          type: 'number',
          description: 'Task ID to complete',
        },
      },
      required: ['task_id'],
    },
  },
  {
    name: 'vikunja_delete_task',
    description: 'Delete a task',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: {
          type: 'number',
          description: 'Task ID to delete',
        },
      },
      required: ['task_id'],
    },
  },
  {
    name: 'vikunja_search_tasks',
    description: 'Search tasks by keyword',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'vikunja_list_labels',
    description: 'List all labels',
    inputSchema: {
      type: 'object',
      properties: {},
      required: [],
    },
  },
];

// =============================================================================
// Request Handlers
// =============================================================================

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  logger.debug('Listing tools');
  return { tools: TOOLS };
});

// Execute tool
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  logger.info(`Executing tool: ${name}`, { args });

  try {
    let result;

    switch (name) {
      case 'vikunja_list_projects':
        result = await vikunjaClient.listProjects();
        break;

      case 'vikunja_list_tasks':
        result = await vikunjaClient.listTasks(args?.project_id, args?.done);
        break;

      case 'vikunja_create_task':
        result = await vikunjaClient.createTask({
          title: args.title,
          project_id: args.project_id,
          description: args.description,
          priority: args.priority,
          due_date: args.due_date,
        });
        break;

      case 'vikunja_update_task':
        result = await vikunjaClient.updateTask(args.task_id, {
          title: args.title,
          description: args.description,
          done: args.done,
          priority: args.priority,
        });
        break;

      case 'vikunja_complete_task':
        result = await vikunjaClient.updateTask(args.task_id, { done: true });
        break;

      case 'vikunja_delete_task':
        result = await vikunjaClient.deleteTask(args.task_id);
        break;

      case 'vikunja_search_tasks':
        result = await vikunjaClient.searchTasks(args.query);
        break;

      case 'vikunja_list_labels':
        result = await vikunjaClient.listLabels();
        break;

      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  } catch (error) {
    logger.error(`Tool execution failed: ${name}`, { error: error.message });
    return {
      content: [
        {
          type: 'text',
          text: `Error: ${error.message}`,
        },
      ],
      isError: true,
    };
  }
});

// List resources (projects as resources)
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  logger.debug('Listing resources');

  try {
    const projects = await vikunjaClient.listProjects();
    return {
      resources: projects.map((project) => ({
        uri: `vikunja://project/${project.id}`,
        name: project.title,
        description: project.description || `Project: ${project.title}`,
        mimeType: 'application/json',
      })),
    };
  } catch (error) {
    logger.error('Failed to list resources', { error: error.message });
    return { resources: [] };
  }
});

// Read resource (project details with tasks)
server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;
  logger.info(`Reading resource: ${uri}`);

  const match = uri.match(/^vikunja:\/\/project\/(\d+)$/);
  if (!match) {
    throw new Error(`Invalid resource URI: ${uri}`);
  }

  const projectId = parseInt(match[1], 10);
  const tasks = await vikunjaClient.listTasks(projectId);

  return {
    contents: [
      {
        uri,
        mimeType: 'application/json',
        text: JSON.stringify(tasks, null, 2),
      },
    ],
  };
});

// =============================================================================
// Server Startup
// =============================================================================

async function main() {
  logger.info('Starting Vikunja MCP Server');

  // Validate configuration
  if (!process.env.VIKUNJA_API_TOKEN) {
    logger.warn('VIKUNJA_API_TOKEN not set - some operations may fail');
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);

  logger.info('Vikunja MCP Server running on stdio');
}

main().catch((error) => {
  logger.error('Failed to start server', { error: error.message });
  process.exit(1);
});
