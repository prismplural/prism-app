import 'package:prism_plurality/domain/models/member.dart' as domain;

abstract class MemberRepository {
  Future<List<domain.Member>> getAllMembers();
  Stream<List<domain.Member>> watchAllMembers();
  Stream<List<domain.Member>> watchActiveMembers();
  Future<domain.Member?> getMemberById(String id);
  Stream<domain.Member?> watchMemberById(String id);
  Future<void> createMember(domain.Member member);
  Future<void> updateMember(domain.Member member);
  Future<void> deleteMember(String id);
  Future<List<domain.Member>> getMembersByIds(List<String> ids);
  Future<int> getCount();
}
