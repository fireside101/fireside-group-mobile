import '../models/fireside_application.dart';
import 'catalogue_repository.dart';

/// Serves the bundled catalogue (mirrors the web app's static catalogue).
class LocalCatalogueRepository implements CatalogueRepository {
  @override
  Future<List<FiresideApplication>> fetchCatalogue() async {
    return catalogue;
  }
}

const List<FiresideApplication> catalogue = [
  FiresideApplication(
    id: 'warehouse',
    name: 'Warehouse',
    department: 'Operations',
    description: 'Track inventory levels, stock movements and warehouse tasks.',
    category: 'featured',
    url: 'https://warehouse.fireside.africa',
    healthUrl: 'https://warehouse.fireside.africa/api/health',
    keywords: ['inventory', 'stock', 'warehouse', 'goods', 'operations'],
  ),
  FiresideApplication(
    id: 'scorecard',
    name: 'Scorecard',
    department: 'Operations',
    description: 'Daily operational scorecards per site and team.',
    category: 'featured',
    url: 'https://scorecard.fireside.africa',
    healthUrl: 'https://scorecard.fireside.africa/api/health',
    keywords: ['scorecard', 'kpi', 'operations', 'targets'],
  ),
  FiresideApplication(
    id: 'operations-scoreboard',
    name: 'Operations Scoreboard',
    department: 'Operations',
    description: 'Live operational scoreboard across all sites.',
    category: 'featured',
    url: 'https://scoreboard.fireside.africa',
    healthUrl: 'https://scoreboard.fireside.africa/api/health',
    keywords: ['scoreboard', 'live', 'operations', 'dashboard'],
    isTall: true,
  ),
  FiresideApplication(
    id: 'tadhkara',
    name: 'Tadhkara',
    department: 'People',
    description: 'Recognise colleagues and celebrate wins across the team.',
    category: 'featured',
    url: 'https://tadhkara.fireside.africa',
    healthUrl: 'https://tadhkara.fireside.africa/api/health',
    keywords: ['recognition', 'people', 'shoutout', 'celebrate'],
  ),
  FiresideApplication(
    id: 'planning-tracker',
    name: 'Planning Tracker',
    department: 'Commercial',
    description: 'Track planning activities, milestones and owner follow-ups.',
    category: 'featured',
    url: 'https://planning.fireside.africa',
    healthUrl: 'https://planning.fireside.africa/api/health',
    keywords: ['planning', 'commercial', 'milestones', 'tracker'],
  ),
  FiresideApplication(
    id: 'people-directory',
    name: 'People Directory',
    department: 'People',
    description: 'Find colleagues, teams and contact details.',
    category: 'featured',
    url: 'https://directory.fireside.africa',
    healthUrl: 'https://directory.fireside.africa/api/health',
    keywords: ['people', 'directory', 'contacts', 'staff'],
  ),
  FiresideApplication(
    id: 'fireside-bi',
    name: 'Fireside BI Reporting',
    department: 'Analytics',
    description: 'Business intelligence dashboards and reports.',
    category: 'platform',
    repository: 'Internal service',
    keywords: ['bi', 'analytics', 'reports', 'dashboard'],
  ),
  FiresideApplication(
    id: 'attendance-ptw',
    name: 'Attendance PTW',
    department: 'Operations',
    description: 'Attendance capture and Permit to Work approvals.',
    category: 'platform',
    url: 'https://attendance.fireside.africa',
    healthUrl: 'https://attendance.fireside.africa/api/health',
    keywords: ['attendance', 'ptw', 'permits', 'ops'],
  ),
  FiresideApplication(
    id: 'maintenance-tracker',
    name: 'Maintenance Tracker',
    department: 'Engineering',
    description: 'Track maintenance requests, jobs and asset uptime.',
    category: 'platform',
    url: 'https://maintenance.fireside.africa',
    healthUrl: 'https://maintenance.fireside.africa/api/health',
    keywords: ['maintenance', 'assets', 'engineering', 'repairs'],
  ),
];